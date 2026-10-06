/**
 * In-memory stand-in for the parts of the Google Calendar API ProTask uses.
 * Behaves like the real thing where it matters for sync: etags change on every write,
 * deleted events stay visible as "cancelled" to incremental syncs, sync tokens can expire (410),
 * and If-Match updates fail with 412 when the event changed.
 */

type Time = { date?: string; dateTime?: string; timeZone?: string };
export type FakeEvent = {
  id: string;
  calendarId: string;
  etag: string;
  updated: string;
  status: "confirmed" | "cancelled";
  summary: string;
  description?: string;
  start: Time;
  end: Time;
  extendedProperties?: { private?: Record<string, string> };
  seq: number;
};

type Body = Omit<FakeEvent, "id" | "calendarId" | "etag" | "updated" | "status" | "seq">;

const httpError = (status: number, message = `HTTP ${status}`) =>
  Object.assign(new Error(message), { response: { status }, code: status });

export const fake = {
  events: new Map<string, FakeEvent>(),
  calls: [] as unknown[][],
  seq: 0,
  ids: 0,
  /** Wall clock used for "updated"; tests move it forward to order edits. */
  now: Date.parse("2026-10-05T12:00:00Z"),
  expiredTokens: new Set<string>(),
  authFailure: false,

  reset() {
    this.events.clear();
    this.calls.length = 0;
    this.seq = 0;
    this.ids = 0;
    this.now = Date.parse("2026-10-05T12:00:00Z");
    this.expiredTokens.clear();
    this.authFailure = false;
  },

  tick(ms = 60_000) {
    this.now += ms;
  },

  stamp(e: FakeEvent) {
    e.seq = ++this.seq;
    e.etag = `"etag-${e.seq}"`;
    e.updated = new Date(this.now).toISOString();
  },

  /** Simulate the user editing an event in Google Calendar. */
  remoteEdit(id: string, patch: Partial<Body>) {
    const e = this.events.get(id)!;
    Object.assign(e, patch);
    this.stamp(e);
  },

  /** Simulate the user deleting an event in Google Calendar. */
  remoteDelete(id: string) {
    const e = this.events.get(id)!;
    e.status = "cancelled";
    this.stamp(e);
  },

  live(calendarId = "cal-top3") {
    return [...this.events.values()].filter((e) => e.calendarId === calendarId && e.status === "confirmed");
  },
};

function guard() {
  if (fake.authFailure) throw Object.assign(new Error("invalid_grant"), { response: { status: 400, data: { error: "invalid_grant" } } });
}

const events = {
  async insert({ calendarId, requestBody }: { calendarId: string; requestBody: Body }) {
    guard();
    const e = { ...structuredClone(requestBody), id: `ev${++fake.ids}`, calendarId, status: "confirmed" } as FakeEvent;
    fake.stamp(e);
    fake.events.set(e.id, e);
    fake.calls.push(["insert", requestBody.summary, requestBody.start.date ?? requestBody.start.dateTime]);
    return { data: structuredClone(e) };
  },
  async update(
    { calendarId, eventId, requestBody }: { calendarId: string; eventId: string; requestBody: Body },
    opts?: { headers?: Record<string, string> },
  ) {
    guard();
    const e = fake.events.get(eventId);
    if (!e || e.calendarId !== calendarId) throw httpError(404);
    if (e.status === "cancelled") throw httpError(410);
    const ifMatch = opts?.headers?.["If-Match"];
    if (ifMatch && ifMatch !== e.etag) throw httpError(412, "Precondition Failed");
    Object.assign(e, structuredClone(requestBody));
    fake.stamp(e);
    fake.calls.push(["update", eventId, requestBody.summary, requestBody.start.date ?? requestBody.start.dateTime]);
    return { data: structuredClone(e) };
  },
  async get({ calendarId, eventId }: { calendarId: string; eventId: string }) {
    guard();
    const e = fake.events.get(eventId);
    if (!e || e.calendarId !== calendarId) throw httpError(404);
    return { data: structuredClone(e) };
  },
  async delete({ calendarId, eventId }: { calendarId: string; eventId: string }) {
    guard();
    const e = fake.events.get(eventId);
    if (!e || e.calendarId !== calendarId) throw httpError(404);
    if (e.status === "cancelled") throw httpError(410);
    e.status = "cancelled";
    fake.stamp(e);
    fake.calls.push(["delete", eventId]);
    return {};
  },
  async list(p: { calendarId: string; syncToken?: string; showDeleted?: boolean; pageToken?: string }) {
    guard();
    if (p.calendarId === "primary") return { data: { items: [] } };
    fake.calls.push(["list", p.syncToken ? "incremental" : "full", p.calendarId]);
    if (p.syncToken && fake.expiredTokens.has(p.syncToken)) throw httpError(410, "Sync token is no longer valid");
    const since = p.syncToken ? Number(p.syncToken.slice(1)) : 0;
    const items = [...fake.events.values()]
      .filter((e) => e.calendarId === p.calendarId)
      .filter((e) => (p.syncToken ? e.seq > since : p.showDeleted || e.status === "confirmed"))
      .map((e) => structuredClone(e));
    return { data: { items, nextSyncToken: `s${fake.seq}` } };
  },
};

export const googleapisMock = {
  google: {
    auth: {
      OAuth2: class {
        setCredentials() {}
        on() {}
        revokeToken() {
          return Promise.resolve();
        }
      },
    },
    calendar: () => ({
      events,
      calendars: { get: async () => ({ data: {} }), insert: async () => ({ data: { id: "cal-top3" } }) },
      calendarList: { list: async () => ({ data: { items: [] } }) },
    }),
  },
};
