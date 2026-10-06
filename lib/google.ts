import { google, type calendar_v3 } from "googleapis";
import { buildEvents, contentHash, LINK_KINDS, type EventBody, type LinkKind } from "./calendarEvent";
import { prisma } from "./db";
import { migrateLegacyLinks } from "./eventLinks";
import { dayKey, parseKey } from "./day";
import type { CalEvent } from "./freeTime";
import { CALENDAR_NAME, googleConfigured, redirectUri } from "./googleConfig";
import { describeError, logError } from "./redact";
import { decide, remotePatch, versionOf, type RemoteEvent } from "./syncLogic";
import { clearTokens, getTokens, saveTokens, updateTokens } from "./tokenStore";

const SCOPES = ["openid", "email", "https://www.googleapis.com/auth/calendar"];
const timeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;

function oauthClient() {
  return new google.auth.OAuth2(process.env.GOOGLE_CLIENT_ID, process.env.GOOGLE_CLIENT_SECRET, redirectUri());
}

export function authUrl(state: string) {
  return oauthClient().generateAuthUrl({ access_type: "offline", prompt: "consent", scope: SCOPES, state });
}

function emailFromIdToken(idToken?: string | null): string | null {
  try {
    const payload = JSON.parse(Buffer.from(idToken!.split(".")[1], "base64url").toString());
    return typeof payload.email === "string" ? payload.email : null;
  } catch {
    return null;
  }
}

/** Exchange the OAuth code, store tokens, and make sure the "Top 3" calendar exists. */
export async function connectWithCode(code: string) {
  const client = oauthClient();
  const { tokens } = await client.getToken(code);
  const existing = await prisma.googleAccount.findUnique({ where: { id: 1 } });
  const refreshToken = tokens.refresh_token ?? (await getTokens())?.refreshToken;
  if (!refreshToken) {
    throw new Error(
      "Google didn't return a refresh token. Remove Top 3 at myaccount.google.com/permissions and connect again.",
    );
  }
  // Tokens go to the Keychain (or encrypted storage); the database only keeps the email and calendar id.
  await saveTokens({ refreshToken, accessToken: tokens.access_token ?? null, expiresAt: tokens.expiry_date ?? null });
  const data = { email: emailFromIdToken(tokens.id_token) ?? existing?.email ?? null, needsReconnect: false };
  await prisma.googleAccount.upsert({ where: { id: 1 }, create: { id: 1, ...data }, update: data });
  const ctx = await getContext();
  if (ctx) await ensureCalendar(ctx);
}

export async function disconnect() {
  const acct = await prisma.googleAccount.findUnique({ where: { id: 1 } });
  const tokens = await getTokens();
  if (tokens) {
    await oauthClient()
      .revokeToken(tokens.refreshToken)
      .catch(() => {});
  }
  await clearTokens();
  if (!acct) return;
  // Keep event links: reconnecting finds the same "Top 3" calendar and updates those events.
  await prisma.googleAccount.delete({ where: { id: 1 } });
}

type Ctx = { cal: calendar_v3.Calendar; calendarId: string | null };

async function getContext(): Promise<Ctx | null> {
  if (!googleConfigured()) return null;
  const acct = await prisma.googleAccount.findUnique({ where: { id: 1 } });
  if (!acct) return null;
  const tokens = await getTokens();
  if (!tokens) return null;
  const client = oauthClient();
  client.setCredentials({
    refresh_token: tokens.refreshToken,
    access_token: tokens.accessToken ?? undefined,
    expiry_date: tokens.expiresAt ?? undefined,
  });
  client.on("tokens", (t) => {
    updateTokens({
      ...(t.access_token ? { accessToken: t.access_token } : {}),
      ...(t.expiry_date ? { expiresAt: t.expiry_date } : {}),
      ...(t.refresh_token ? { refreshToken: t.refresh_token } : {}),
    }).catch((e) => logError("calendar", e));
  });
  return { cal: google.calendar({ version: "v3", auth: client }), calendarId: acct.calendarId };
}

function status(e: unknown): number | undefined {
  const err = e as { code?: number | string; status?: number; response?: { status?: number } };
  return err?.response?.status ?? err?.status ?? (typeof err?.code === "number" ? err.code : undefined);
}

/** Find or create the dedicated "Top 3" calendar and remember its id. */
async function ensureCalendar(ctx: Ctx): Promise<string> {
  if (ctx.calendarId) {
    try {
      await ctx.cal.calendars.get({ calendarId: ctx.calendarId });
      return ctx.calendarId;
    } catch (e) {
      if (status(e) !== 404) throw e;
    }
  }
  const list = await ctx.cal.calendarList.list({ minAccessRole: "owner", maxResults: 250 });
  let id = list.data.items?.find((c) => c.summary === CALENDAR_NAME)?.id ?? null;
  if (!id) {
    const created = await ctx.cal.calendars.insert({
      requestBody: {
        summary: CALENDAR_NAME,
        description: "Tasks and daily focus from the Top 3 app",
        timeZone: timeZone(),
      },
    });
    id = created.data.id!;
  }
  await prisma.googleAccount.update({ where: { id: 1 }, data: { calendarId: id } });
  ctx.calendarId = id;
  return id;
}

/** Google refused our tokens (revoked, or the refresh token expired): ask the user to reconnect. */
function isAuthError(e: unknown): boolean {
  const err = e as { response?: { status?: number; data?: { error?: unknown } }; message?: string };
  return (
    err?.response?.data?.error === "invalid_grant" ||
    err?.message === "invalid_grant" ||
    status(e) === 401
  );
}

async function markNeedsReconnect() {
  await prisma.googleAccount.updateMany({ where: { id: 1 }, data: { needsReconnect: true } });
}

type TaskWithLinks = NonNullable<Awaited<ReturnType<typeof loadTask>>>;
type Link = TaskWithLinks["links"][number];

function loadTask(taskId: string) {
  return prisma.task.findUnique({ where: { id: taskId }, include: { links: true } });
}

async function syncOne(taskId: string, retried = false): Promise<void> {
  const ctx = await getContext();
  if (!ctx) return;
  await migrateLegacyLinks();
  const task = await loadTask(taskId);
  if (!task) return;
  try {
    const calendarId = await ensureCalendar(ctx);
    const desired = buildEvents(task, dayKey(), timeZone());
    for (const kind of LINK_KINDS) {
      const body = desired[kind];
      const link = task.links.find((l) => l.kind === kind);
      if (!body) {
        if (link) {
          await deleteRemote(ctx, calendarId, link.eventId);
          await prisma.eventLink.deleteMany({ where: { id: link.id } });
        }
        continue;
      }
      const hash = contentHash(body);
      if (link) {
        if (link.contentHash === hash) continue; // calendar already shows this
        let recreate = false;
        try {
          // If-Match: only overwrite the version we last saw. A calendar edit since then fails with 412.
          const res = await ctx.cal.events.update(
            { calendarId, eventId: link.eventId, requestBody: body },
            link.etag ? { headers: { "If-Match": link.etag } } : undefined,
          );
          await saveLink(link.id, res.data, hash);
        } catch (e) {
          const code = status(e);
          if (code === 412 && !retried) {
            // Edited in the calendar since our last sync: resolve that first, then push whatever still differs.
            const remote = await ctx.cal.events.get({ calendarId, eventId: link.eventId });
            await resolveRemote(task, link, remote.data);
            return syncOne(taskId, true);
          }
          if (code === 410) {
            // Deleted in the calendar: keep the task, mark it unscheduled.
            await remoteDeleted(task, link, body);
            continue;
          }
          if (code !== 404) throw e;
          // Not in this calendar at all (e.g. reconnected with another account): create it again below.
          await prisma.eventLink.deleteMany({ where: { id: link.id } });
          recreate = true;
        }
        if (!recreate) continue;
      }
      const res = await ctx.cal.events.insert({ calendarId, requestBody: body });
      await prisma.eventLink.create({
        data: { taskId, kind, eventId: res.data.id!, ...linkFields(res.data, hash) },
      });
    }
    if (task.syncError) await prisma.task.updateMany({ where: { id: taskId }, data: { syncError: null } });
  } catch (e) {
    logError("calendar sync", e);
    if (isAuthError(e)) await markNeedsReconnect();
    await prisma.task.updateMany({ where: { id: taskId }, data: { syncError: describeError(e) } });
  }
}

type RemoteMeta = { etag?: string | null; updated?: string | null };

function linkFields(ev: RemoteMeta, hash: string | null) {
  return {
    etag: ev.etag ?? null,
    contentHash: hash,
    remoteUpdatedAt: ev.updated ? new Date(ev.updated) : null,
    lastSyncedAt: new Date(),
  };
}

function saveLink(id: string, ev: RemoteMeta, hash: string | null) {
  return prisma.eventLink.update({ where: { id }, data: linkFields(ev, hash) });
}

const HISTORY_LIMIT = 200;

async function logHistory(entry: { taskId: string; taskTitle: string; reason: string; winner?: string; lost: string }) {
  await prisma.syncHistory.create({ data: entry });
  const old = await prisma.syncHistory.findMany({ orderBy: { at: "desc" }, skip: HISTORY_LIMIT, select: { id: true } });
  if (old.length) await prisma.syncHistory.deleteMany({ where: { id: { in: old.map((o) => o.id) } } });
}

/**
 * The event was deleted in the calendar. The task stays: it is marked unscheduled, shown on Today,
 * and gets no new events until it is rescheduled. The last synced version goes to sync history.
 */
async function remoteDeleted(task: TaskWithLinks, link: Link, lastKnown?: EventBody | null) {
  await prisma.eventLink.deleteMany({ where: { id: link.id } });
  await prisma.task.updateMany({ where: { id: task.id }, data: { unscheduled: true } });
  await logHistory({
    taskId: task.id,
    taskTitle: task.title,
    reason: "deleted-in-calendar",
    lost: versionOf(lastKnown ?? buildEvents({ ...task, unscheduled: false }, dayKey())[link.kind as LinkKind]),
  });
}

/** Apply one changed calendar event to its task, following the conflict rule in decide(). */
async function resolveRemote(task: TaskWithLinks, link: Link, ev: RemoteEvent): Promise<boolean> {
  if (ev.status === "cancelled") {
    await remoteDeleted(task, link);
    return true;
  }
  const today = dayKey();
  const local = buildEvents(task, today, timeZone())[link.kind as LinkKind];
  const decision = decide(link, ev, local, task.updatedAt);
  const remoteHash = contentHash(ev);

  if (decision === "unchanged" || decision === "converged") {
    await saveLink(link.id, ev, decision === "converged" ? remoteHash : link.contentHash);
    return false;
  }
  if (decision === "local-wins") {
    // Keep the task's version and push it next, with the calendar's current etag. Log what the calendar had.
    await logHistory({ taskId: task.id, taskTitle: task.title, reason: "conflict", winner: "protask", lost: versionOf(ev) });
    await prisma.eventLink.update({ where: { id: link.id }, data: { etag: ev.etag ?? null, remoteUpdatedAt: ev.updated ? new Date(ev.updated) : null } });
    return true;
  }
  // "pull" or "remote-wins": the calendar's version goes into the task.
  if (decision === "remote-wins") {
    await logHistory({ taskId: task.id, taskTitle: task.title, reason: "conflict", winner: "calendar", lost: versionOf(local) });
  }
  const pinDay = task.topSlot != null && task.topDate === today ? today : null;
  const { patch, pinnedMoved } = remotePatch(link.kind, ev, task, pinDay);
  if (pinnedMoved) {
    await logHistory({ taskId: task.id, taskTitle: task.title, reason: "pinned-moved", winner: "protask", lost: versionOf(ev) });
  }
  if (Object.keys(patch).length) await prisma.task.update({ where: { id: task.id }, data: { ...patch, unscheduled: false } });
  // Remember the calendar's version as agreed; anything ProTask still wants different is pushed next.
  await saveLink(link.id, ev, remoteHash);
  return true;
}

let pullChain: Promise<unknown> = Promise.resolve();
const MIN_PULL_INTERVAL_MS = 15_000;

/**
 * Pull calendar edits into tasks. Only the dedicated "Top 3" calendar is read, incrementally with
 * Google's sync token; an expired token (410) falls back to a full resync. Returns the ids of tasks
 * that changed. Never throws.
 */
export function pullChanges(opts: { force?: boolean } = {}): Promise<string[]> {
  const run = pullChain.then(() => pullOnce(opts.force ?? false), () => pullOnce(opts.force ?? false));
  pullChain = run.catch(() => {});
  return run;
}

async function pullOnce(force: boolean): Promise<string[]> {
  const ctx = await getContext();
  if (!ctx) return [];
  const acct = await prisma.googleAccount.findUniqueOrThrow({ where: { id: 1 } });
  if (!force && acct.lastPulledAt && Date.now() - acct.lastPulledAt.getTime() < MIN_PULL_INTERVAL_MS) return [];
  await migrateLegacyLinks();
  try {
    const calendarId = await ensureCalendar(ctx);
    // Only a resync after an expired token may treat "not listed" as deleted. On a first sync
    // (e.g. after reconnecting with another account) links may point at events that never existed here.
    let resync = false;
    let listed: { items: RemoteEvent[]; nextSyncToken: string | null };
    try {
      listed = await listEvents(ctx, calendarId, acct.syncToken);
    } catch (e) {
      if (status(e) !== 410) throw e;
      resync = true; // sync token expired: start over with a full list
      listed = await listEvents(ctx, calendarId, null);
    }

    const links = await prisma.eventLink.findMany();
    const byEvent = new Map(links.map((l) => [l.eventId, l]));
    const seen = new Set<string>();
    const changed = new Set<string>();
    for (const ev of listed.items) {
      const link = ev.id ? byEvent.get(ev.id) : undefined;
      if (!link) continue; // not one of ours (or already unlinked)
      seen.add(link.eventId);
      if (ev.status !== "cancelled" && ev.etag && ev.etag === link.etag) continue; // our own write
      await enqueue(link.taskId, async () => {
        const task = await loadTask(link.taskId);
        const fresh = task?.links.find((l) => l.id === link.id);
        if (task && fresh && (await resolveRemote(task, fresh, ev))) changed.add(task.id);
      });
    }
    if (resync) {
      // After a full list, a linked event that wasn't returned no longer exists.
      for (const link of links) {
        if (seen.has(link.eventId)) continue;
        await enqueue(link.taskId, async () => {
          const task = await loadTask(link.taskId);
          const fresh = task?.links.find((l) => l.id === link.id);
          if (task && fresh) {
            await remoteDeleted(task, fresh);
            changed.add(task.id);
          }
        });
      }
    }
    await prisma.googleAccount.update({
      where: { id: 1 },
      data: { syncToken: listed.nextSyncToken, lastPulledAt: new Date(), needsReconnect: false },
    });
    if (changed.size) await syncTasks(changed); // push anything ProTask still wants different
    return [...changed];
  } catch (e) {
    logError("calendar pull", e);
    if (isAuthError(e)) await markNeedsReconnect();
    return [];
  }
}

async function listEvents(ctx: Ctx, calendarId: string, syncToken: string | null) {
  const items: RemoteEvent[] = [];
  let pageToken: string | undefined;
  let nextSyncToken: string | null = null;
  do {
    const res = await ctx.cal.events.list({
      calendarId,
      showDeleted: true,
      maxResults: 250,
      ...(syncToken ? { syncToken } : {}),
      ...(pageToken ? { pageToken } : {}),
    });
    items.push(...((res.data.items ?? []) as RemoteEvent[]));
    pageToken = res.data.nextPageToken ?? undefined;
    nextSyncToken = res.data.nextSyncToken ?? nextSyncToken;
  } while (pageToken);
  return { items, nextSyncToken };
}

async function deleteRemote(ctx: Ctx, calendarId: string, eventId: string) {
  try {
    await ctx.cal.events.delete({ calendarId, eventId });
  } catch (e) {
    if (status(e) !== 404 && status(e) !== 410) throw e;
  }
}

// One promise chain per task, so rapid edits can't race and create duplicate events.
const chains = new Map<string, Promise<void>>();
function enqueue(key: string, job: () => Promise<void>) {
  const next = (chains.get(key) ?? Promise.resolve()).then(job, job).catch(() => {});
  chains.set(key, next);
  next.then(() => chains.get(key) === next && chains.delete(key));
  return next;
}

/** Bring the calendar events of these tasks in line with the database. Never throws. */
export function syncTasks(ids: Iterable<string>) {
  return Promise.all([...new Set(ids)].map((id) => enqueue(id, () => syncOne(id))));
}

/** Remove every event of a task that no longer exists. */
export function deleteEventsFor(taskId: string, eventIds: string[]) {
  if (!eventIds.length) return Promise.resolve();
  return enqueue(taskId, async () => {
    const ctx = await getContext();
    if (!ctx) return;
    try {
      const calendarId = await ensureCalendar(ctx);
      for (const id of eventIds) await deleteRemote(ctx, calendarId, id);
    } catch (e) {
      logError("calendar delete", e);
    }
  });
}

/** After connecting: create events for every task that should have one. */
export async function backfill() {
  await migrateLegacyLinks();
  const today = dayKey();
  const tasks = await prisma.task.findMany({
    where: {
      OR: [{ dueAt: { not: null } }, { topDate: today, topSlot: { not: null } }, { links: { some: {} } }],
    },
    select: { id: true },
  });
  await syncTasks(tasks.map((t) => t.id));
}

/** Today's events from the user's primary calendar (calendar day, midnight to midnight). */
export async function todaysEvents(): Promise<CalEvent[] | null> {
  const ctx = await getContext();
  if (!ctx) return null;
  const start = parseKey(dayKey(new Date(), 0));
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  const res = await ctx.cal.events.list({
    calendarId: "primary",
    timeMin: start.toISOString(),
    timeMax: end.toISOString(),
    singleEvents: true,
    orderBy: "startTime",
    maxResults: 50,
  });
  return (res.data.items ?? [])
    .filter((e) => e.status !== "cancelled" && e.transparency !== "transparent")
    .map((e) => ({
      id: e.id ?? crypto.randomUUID(),
      title: e.summary ?? "(busy)",
      allDay: !e.start?.dateTime,
      start: e.start?.dateTime ?? parseKey(e.start?.date ?? dayKey()).toISOString(),
      end: e.end?.dateTime ?? parseKey(e.end?.date ?? dayKey()).toISOString(),
    }));
}
