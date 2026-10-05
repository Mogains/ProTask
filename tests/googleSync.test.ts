import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("googleapis", async () => (await import("./fakeGoogle")).googleapisMock);

import { prisma } from "@/lib/db";
import { addDays, dayKey, parseKey } from "@/lib/day";
import { deleteEventsFor, syncTasks } from "@/lib/google";
import { saveTokens } from "@/lib/tokenStore";
import { fake } from "./fakeGoogle";

const newTask = (data: Partial<Parameters<typeof prisma.task.create>[0]["data"]> = {}) =>
  prisma.task.create({ data: { title: "Pay rent", list: "HAVE_TO", position: 1000, ...data } });
const links = (taskId: string) => prisma.eventLink.findMany({ where: { taskId }, orderBy: { kind: "asc" } });
const today = () => dayKey();
const tomorrow = () => parseKey(addDays(dayKey(), 1));

describe("Google Calendar sync (push)", () => {
  beforeEach(async () => {
    fake.reset();
    await prisma.eventLink.deleteMany();
    await prisma.task.deleteMany();
    await prisma.googleAccount.deleteMany();
    await prisma.googleAccount.create({ data: { id: 1, calendarId: "cal-top3" } });
    await saveTokens({ refreshToken: "r" });
  });

  it("creates, updates with a checkmark, and deletes an event for a dated task", async () => {
    const t = await newTask({ dueAt: new Date(2026, 9, 6) });
    await syncTasks([t.id]);
    const [link] = await links(t.id);
    expect(fake.calls).toEqual([["insert", "Pay rent", "2026-10-06"]]);
    expect(link).toMatchObject({ kind: "DUE", eventId: "ev1" });
    expect(link.etag).toBeTruthy();
    expect(link.contentHash).toBeTruthy();

    await prisma.task.update({ where: { id: t.id }, data: { completed: true, completedAt: new Date() } });
    await syncTasks([t.id]);
    expect(fake.calls[1]).toEqual(["update", "ev1", "✅ Pay rent", "2026-10-06"]);

    await prisma.task.delete({ where: { id: t.id } });
    await deleteEventsFor(t.id, [link.eventId]);
    expect(fake.calls[2]).toEqual(["delete", "ev1"]);
  });

  it("skips the API call when nothing visible changed", async () => {
    const t = await newTask({ dueAt: new Date(2026, 9, 6) });
    await syncTasks([t.id]);
    await prisma.task.update({ where: { id: t.id }, data: { position: 5 } });
    await syncTasks([t.id]);
    expect(fake.calls).toHaveLength(1);
  });

  it("does nothing when Google isn't connected", async () => {
    await prisma.googleAccount.deleteMany();
    const t = await newTask({ dueAt: new Date() });
    await syncTasks([t.id]);
    expect(fake.calls).toEqual([]);
  });

  it("serialises rapid syncs so a task never gets two events of a kind", async () => {
    const t = await newTask({ dueAt: new Date() });
    await Promise.all([syncTasks([t.id]), syncTasks([t.id]), syncTasks([t.id])]);
    expect(fake.calls.filter((c) => c[0] === "insert")).toHaveLength(1);
  });

  it("migrates an old single calendarEventId into a link", async () => {
    const t = await newTask({ dueAt: new Date(2026, 9, 6) });
    await syncTasks([t.id]);
    const [link] = await links(t.id);
    // Rewind to the pre-links shape: one id on the task, no link rows.
    await prisma.eventLink.deleteMany();
    await prisma.task.update({ where: { id: t.id }, data: { calendarEventId: link.eventId } });
    await prisma.task.update({ where: { id: t.id }, data: { title: "Pay rent today" } });
    await syncTasks([t.id]);
    const after = await links(t.id);
    expect(after).toMatchObject([{ kind: "DUE", eventId: link.eventId }]);
    expect((await prisma.task.findUniqueOrThrow({ where: { id: t.id } })).calendarEventId).toBeNull();
    expect(fake.calls.at(-1)).toEqual(["update", link.eventId, "Pay rent today", "2026-10-06"]);
    expect(fake.live()).toHaveLength(1); // updated in place, no duplicate
  });
});

describe("multiple events per task", () => {
  beforeEach(async () => {
    fake.reset();
    await prisma.eventLink.deleteMany();
    await prisma.task.deleteMany();
    await prisma.googleAccount.deleteMany();
    await prisma.googleAccount.create({ data: { id: 1, calendarId: "cal-top3" } });
    await saveTokens({ refreshToken: "r" });
  });

  it("pin: a task due tomorrow pinned today gets a pinned event today and keeps its due event", async () => {
    const t = await newTask({ dueAt: tomorrow() });
    await syncTasks([t.id]);
    await prisma.task.update({ where: { id: t.id }, data: { topSlot: 1, topDate: today() } });
    await syncTasks([t.id]);
    expect((await links(t.id)).map((l) => l.kind)).toEqual(["DUE", "PINNED"]);
    const live = fake.live().map((e) => [e.summary, e.start.date]);
    expect(live).toEqual([
      ["Pay rent", addDays(today(), 1)],
      ["⭐ Pay rent", today()],
    ]);
  });

  it("pin: a task due today pinned today gets one starred event, not two", async () => {
    const t = await newTask({ dueAt: parseKey(today()), topSlot: 2, topDate: today() });
    await syncTasks([t.id]);
    expect((await links(t.id)).map((l) => l.kind)).toEqual(["DUE"]);
    expect(fake.live().map((e) => e.summary)).toEqual(["⭐ Pay rent"]);
  });

  it("unpin removes only the pinned event", async () => {
    const t = await newTask({ dueAt: tomorrow(), topSlot: 1, topDate: today() });
    await syncTasks([t.id]);
    const before = await links(t.id);
    await prisma.task.update({ where: { id: t.id }, data: { topSlot: null, topDate: null } });
    await syncTasks([t.id]);
    const pinned = before.find((l) => l.kind === "PINNED")!;
    expect(fake.calls.filter((c) => c[0] === "delete")).toEqual([["delete", pinned.eventId]]);
    expect((await links(t.id)).map((l) => l.kind)).toEqual(["DUE"]);
    expect(fake.live().map((e) => e.summary)).toEqual(["Pay rent"]);
  });

  it("move: changing the due date moves the due event and leaves the pinned event alone", async () => {
    const t = await newTask({ dueAt: tomorrow(), topSlot: 1, topDate: today() });
    await syncTasks([t.id]);
    const pinned = (await links(t.id)).find((l) => l.kind === "PINNED")!;
    fake.calls.length = 0;
    await prisma.task.update({ where: { id: t.id }, data: { dueAt: parseKey(addDays(today(), 3)) } });
    await syncTasks([t.id]);
    expect(fake.calls).toEqual([["update", "ev1", "Pay rent", addDays(today(), 3)]]);
    expect(fake.events.get(pinned.eventId)!.start.date).toBe(today());
  });

  it("move: moving the due date onto the pin day merges into one starred event", async () => {
    const t = await newTask({ dueAt: tomorrow(), topSlot: 1, topDate: today() });
    await syncTasks([t.id]);
    await prisma.task.update({ where: { id: t.id }, data: { dueAt: parseKey(today()) } });
    await syncTasks([t.id]);
    expect((await links(t.id)).map((l) => l.kind)).toEqual(["DUE"]);
    expect(fake.live().map((e) => [e.summary, e.start.date])).toEqual([["⭐ Pay rent", today()]]);
  });

  it("complete marks every linked event done", async () => {
    const t = await newTask({ dueAt: tomorrow(), topSlot: 1, topDate: today() });
    await syncTasks([t.id]);
    await prisma.task.update({ where: { id: t.id }, data: { completed: true, completedAt: new Date() } });
    await syncTasks([t.id]);
    expect(fake.live().map((e) => e.summary)).toEqual(["✅ Pay rent", "✅ Pay rent"]);
  });

  it("delete removes every linked event", async () => {
    const t = await newTask({ dueAt: tomorrow(), topSlot: 1, topDate: today() });
    await syncTasks([t.id]);
    const ids = (await links(t.id)).map((l) => l.eventId);
    await prisma.task.delete({ where: { id: t.id } });
    expect(await prisma.eventLink.count()).toBe(0); // cascades
    await deleteEventsFor(t.id, ids);
    expect(fake.live()).toEqual([]);
  });
});
