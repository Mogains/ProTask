import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("googleapis", async () => (await import("./fakeGoogle")).googleapisMock);

import { prisma } from "@/lib/db";
import { addDays, dayKey, parseKey } from "@/lib/day";
import { pullChanges, syncTasks } from "@/lib/google";
import { saveTokens } from "@/lib/tokenStore";
import { fake } from "./fakeGoogle";

const newTask = (data: Partial<Parameters<typeof prisma.task.create>[0]["data"]> = {}) =>
  prisma.task.create({ data: { title: "Pay rent", list: "HAVE_TO", position: 1000, ...data } });
const getTask = (id: string) => prisma.task.findUniqueOrThrow({ where: { id } });
const links = (taskId: string) => prisma.eventLink.findMany({ where: { taskId }, orderBy: { kind: "asc" } });
const history = () => prisma.syncHistory.findMany({ orderBy: { at: "asc" } });
const account = () => prisma.googleAccount.findUniqueOrThrow({ where: { id: 1 } });
const pull = () => pullChanges({ force: true });
const today = () => dayKey();
const inDays = (n: number) => addDays(dayKey(), n);
const writes = () => fake.calls.filter((c) => c[0] !== "list");

/** A dated task, pushed to the calendar, with the first pull done so a sync token exists. */
async function syncedTask(data: Parameters<typeof newTask>[0] = {}) {
  const t = await newTask({ dueAt: parseKey(inDays(1)), ...data });
  await syncTasks([t.id]);
  await pull();
  fake.calls.length = 0;
  return { task: await getTask(t.id), link: (await links(t.id))[0] };
}

/** Calendar edits stamped before or after ProTask's own edits, which use the real clock. */
const remoteLater = () => (fake.now = Date.now() + 3_600_000);
const remoteEarlier = () => (fake.now = Date.now() - 3_600_000);

describe("two-way sync", () => {
  beforeEach(async () => {
    fake.reset();
    await prisma.syncHistory.deleteMany();
    await prisma.eventLink.deleteMany();
    await prisma.task.deleteMany();
    await prisma.googleAccount.deleteMany();
    await prisma.googleAccount.create({ data: { id: 1, calendarId: "cal-top3" } });
    await saveTokens({ refreshToken: "r" });
  });

  it("remote edit: a new title and date in the calendar are pulled into the task", async () => {
    const { task, link } = await syncedTask();
    fake.remoteEdit(link.eventId, {
      summary: "Pay rent and bills",
      start: { date: inDays(3) },
      end: { date: inDays(4) },
    });
    expect(await pull()).toEqual([task.id]);
    const after = await getTask(task.id);
    expect(after).toMatchObject({ title: "Pay rent and bills", hasDueTime: false });
    expect(after.dueAt).toEqual(parseKey(inDays(3)));
    expect(writes()).toEqual([]); // the calendar already shows it: nothing is pushed back
    expect(await history()).toEqual([]); // no conflict, nothing lost
  });

  it("remote edit: moving and resizing a timed event updates the due time and estimate", async () => {
    const start = new Date(parseKey(inDays(1)).getTime() + 9 * 3_600_000);
    const { task, link } = await syncedTask({ dueAt: start, hasDueTime: true });
    const moved = new Date(start.getTime() + 2 * 3_600_000);
    fake.remoteEdit(link.eventId, {
      start: { dateTime: moved.toISOString() },
      end: { dateTime: new Date(moved.getTime() + 90 * 60_000).toISOString() },
    });
    await pull();
    expect(await getTask(task.id)).toMatchObject({ dueAt: moved, hasDueTime: true, estimateMinutes: 90 });
  });

  it("local edit: pushed out with If-Match, and the next pull treats it as our own write", async () => {
    const { task, link } = await syncedTask();
    await prisma.task.update({ where: { id: task.id }, data: { title: "Pay rent early" } });
    await syncTasks([task.id]);
    expect(writes()).toEqual([["update", link.eventId, "Pay rent early", inDays(1)]]);
    expect(await pull()).toEqual([]);
    expect((await getTask(task.id)).title).toBe("Pay rent early");
    expect(await history()).toEqual([]);
  });

  it("conflict: both edited, the calendar edit is newer, so it wins and ProTask's version is logged", async () => {
    const { task, link } = await syncedTask();
    await prisma.task.update({ where: { id: task.id }, data: { title: "ProTask title" } });
    remoteLater();
    fake.remoteEdit(link.eventId, { summary: "Calendar title" });
    await pull();
    expect((await getTask(task.id)).title).toBe("Calendar title");
    expect(fake.events.get(link.eventId)!.summary).toBe("Calendar title");
    const [h] = await history();
    expect(h).toMatchObject({ reason: "conflict", winner: "calendar", taskId: task.id });
    expect(JSON.parse(h.lost).title).toBe("ProTask title");
  });

  it("conflict: both edited, the ProTask edit is newer, so it wins and the calendar's version is logged", async () => {
    const { task, link } = await syncedTask();
    remoteEarlier();
    fake.remoteEdit(link.eventId, { summary: "Calendar title" });
    await prisma.task.update({ where: { id: task.id }, data: { title: "ProTask title" } });
    await pull();
    expect((await getTask(task.id)).title).toBe("ProTask title");
    expect(fake.events.get(link.eventId)!.summary).toBe("ProTask title"); // pushed with the fresh etag
    const [h] = await history();
    expect(h).toMatchObject({ reason: "conflict", winner: "protask" });
    expect(JSON.parse(h.lost).title).toBe("Calendar title");
  });

  it("conflict found while pushing: a 412 resolves the calendar edit first instead of overwriting it", async () => {
    const { task, link } = await syncedTask();
    await prisma.task.update({ where: { id: task.id }, data: { title: "ProTask title" } });
    remoteLater();
    fake.remoteEdit(link.eventId, { summary: "Calendar title" });
    await syncTasks([task.id]); // push before any pull has seen the calendar edit
    expect(fake.events.get(link.eventId)!.summary).toBe("Calendar title");
    expect((await getTask(task.id)).title).toBe("Calendar title");
    expect((await history()).map((h) => h.winner)).toEqual(["calendar"]);
    expect((await getTask(task.id)).syncError).toBeNull();
  });

  it("remote delete: the task stays, is marked unscheduled, and no event is recreated", async () => {
    const { task, link } = await syncedTask({ topSlot: 1, topDate: today() });
    expect((await links(task.id)).map((l) => l.kind)).toEqual(["DUE", "PINNED"]);
    fake.remoteDelete(link.eventId);
    expect(await pull()).toEqual([task.id]);

    const after = await getTask(task.id);
    expect(after.unscheduled).toBe(true);
    expect(after.title).toBe("Pay rent");
    expect(fake.calls.some((c) => c[0] === "insert")).toBe(false);
    expect(fake.live()).toEqual([]); // the task is off the calendar until rescheduled
    const [h] = await history();
    expect(h).toMatchObject({ reason: "deleted-in-calendar", taskId: task.id });
    expect(JSON.parse(h.lost).title).toBe("Pay rent");

    // Rescheduling puts it back.
    await prisma.task.update({ where: { id: task.id }, data: { unscheduled: false } });
    await syncTasks([task.id]);
    expect(fake.live().map((e) => e.start.date)).toEqual([inDays(1), today()]);
  });

  it("remote delete found while pushing (410) also marks the task unscheduled", async () => {
    const { task, link } = await syncedTask();
    fake.remoteDelete(link.eventId);
    await prisma.task.update({ where: { id: task.id }, data: { title: "Pay rent early" } });
    await syncTasks([task.id]);
    expect((await getTask(task.id)).unscheduled).toBe(true);
    expect(fake.live()).toEqual([]);
  });

  it("an event missing from a new account's calendar (404) is recreated, not treated as deleted", async () => {
    const { task, link } = await syncedTask();
    fake.events.delete(link.eventId);
    await prisma.task.update({ where: { id: task.id }, data: { title: "Pay rent early" } });
    await syncTasks([task.id]);
    expect((await getTask(task.id)).unscheduled).toBe(false);
    expect(fake.live().map((e) => e.summary)).toEqual(["Pay rent early"]);
  });

  it("moving a Top 3 event to another day keeps it on the pin day and logs the move", async () => {
    const { task } = await syncedTask({ dueAt: null, topSlot: 1, topDate: today() });
    const [pinned] = await links(task.id);
    fake.remoteEdit(pinned.eventId, { summary: "⭐ Pay rent now", start: { date: inDays(2) }, end: { date: inDays(3) } });
    await pull();
    expect((await getTask(task.id)).title).toBe("Pay rent now");
    expect(fake.events.get(pinned.eventId)!.start.date).toBe(today());
    expect((await history()).map((h) => h.reason)).toEqual(["pinned-moved"]);
  });

  it("token expiry: an expired sync token (410) falls back to a full resync", async () => {
    const { task, link } = await syncedTask();
    const gone = await syncedTask({ title: "Call mom" });
    fake.expiredTokens.add((await account()).syncToken!);
    fake.remoteEdit(link.eventId, { summary: "Pay rent and bills" });
    fake.events.delete(gone.link.eventId); // purged while the token was stale: only a full list can tell
    fake.calls.length = 0;

    expect((await pull()).sort()).toEqual([task.id, gone.task.id].sort());
    expect(fake.calls.filter((c) => c[0] === "list").map((c) => c[1])).toEqual(["incremental", "full"]);
    expect((await getTask(task.id)).title).toBe("Pay rent and bills");
    expect((await getTask(gone.task.id)).unscheduled).toBe(true);
    expect((await account()).syncToken).not.toBe(null);
  });

  it("token expiry: a revoked OAuth token pauses sync and asks to reconnect, without throwing", async () => {
    const { task } = await syncedTask();
    fake.authFailure = true;
    await expect(pull()).resolves.toEqual([]);
    expect((await account()).needsReconnect).toBe(true);

    await prisma.task.update({ where: { id: task.id }, data: { title: "Pay rent early" } });
    await syncTasks([task.id]);
    expect((await getTask(task.id)).syncError).toBeTruthy();

    fake.authFailure = false;
    await pull();
    expect((await account()).needsReconnect).toBe(false);
  });

  it("only reads and writes the dedicated Top 3 calendar", async () => {
    const { task } = await syncedTask();
    await prisma.task.update({ where: { id: task.id }, data: { title: "Pay rent early" } });
    await syncTasks([task.id]);
    await pull();
    const lists = fake.calls.filter((c) => c[0] === "list");
    expect(lists.length).toBeGreaterThan(0);
    expect(lists.every((c) => c[2] === "cal-top3")).toBe(true);
    expect([...fake.events.values()].every((e) => e.calendarId === "cal-top3")).toBe(true);
  });
});
