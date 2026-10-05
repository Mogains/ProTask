import { google, type calendar_v3 } from "googleapis";
import { buildEvents, contentHash, LINK_KINDS } from "./calendarEvent";
import { prisma } from "./db";
import { migrateLegacyLinks } from "./eventLinks";
import { dayKey, parseKey } from "./day";
import type { CalEvent } from "./freeTime";
import { CALENDAR_NAME, googleConfigured, redirectUri } from "./googleConfig";
import { describeError, logError } from "./redact";
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
  const data = { email: emailFromIdToken(tokens.id_token) ?? existing?.email ?? null };
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

async function syncOne(taskId: string) {
  const ctx = await getContext();
  if (!ctx) return;
  await migrateLegacyLinks();
  const task = await prisma.task.findUnique({ where: { id: taskId }, include: { links: true } });
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
        try {
          const res = await ctx.cal.events.update({ calendarId, eventId: link.eventId, requestBody: body });
          await saveLink(link.id, res.data, hash);
          continue;
        } catch (e) {
          if (status(e) !== 404 && status(e) !== 410) throw e;
          await prisma.eventLink.deleteMany({ where: { id: link.id } }); // gone remotely: recreate below
        }
      }
      const res = await ctx.cal.events.insert({ calendarId, requestBody: body });
      await prisma.eventLink.create({
        data: { taskId, kind, eventId: res.data.id!, ...linkFields(res.data, hash) },
      });
    }
    if (task.syncError) await prisma.task.updateMany({ where: { id: taskId }, data: { syncError: null } });
  } catch (e) {
    logError("calendar sync", e);
    await prisma.task.updateMany({ where: { id: taskId }, data: { syncError: describeError(e) } });
  }
}

type RemoteMeta = { etag?: string | null; updated?: string | null };

function linkFields(ev: RemoteMeta, hash: string) {
  return {
    etag: ev.etag ?? null,
    contentHash: hash,
    remoteUpdatedAt: ev.updated ? new Date(ev.updated) : null,
    lastSyncedAt: new Date(),
  };
}

function saveLink(id: string, ev: RemoteMeta, hash: string) {
  return prisma.eventLink.update({ where: { id }, data: linkFields(ev, hash) });
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
