import { beforeEach, describe, expect, it, vi } from "vitest";

// Fake Google Calendar API that records every call.
const g = vi.hoisted(() => {
  const calls: unknown[][] = [];
  let n = 0;
  const events = {
    insert: async ({ requestBody }: { requestBody: { summary: string } }) => {
      calls.push(["insert", requestBody.summary]);
      return { data: { id: `ev${++n}` } };
    },
    update: async ({ eventId, requestBody }: { eventId: string; requestBody: { summary: string } }) => {
      calls.push(["update", eventId, requestBody.summary]);
      return { data: {} };
    },
    delete: async ({ eventId }: { eventId: string }) => {
      calls.push(["delete", eventId]);
      return {};
    },
  };
  return { calls, events };
});

vi.mock("googleapis", () => ({
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
      events: g.events,
      calendars: { get: async () => ({ data: {} }), insert: async () => ({ data: { id: "cal-top3" } }) },
      calendarList: { list: async () => ({ data: { items: [] } }) },
    }),
  },
}));

import { prisma } from "@/lib/db";
import { dayKey } from "@/lib/day";
import { deleteEventFor, syncTasks } from "@/lib/google";

const newTask = (data: Partial<Parameters<typeof prisma.task.create>[0]["data"]> = {}) =>
  prisma.task.create({ data: { title: "Pay rent", list: "HAVE_TO", position: 1000, ...data } });

describe("Google Calendar sync", () => {
  beforeEach(async () => {
    g.calls.length = 0;
    await prisma.task.deleteMany();
    await prisma.googleAccount.deleteMany();
    await prisma.googleAccount.create({ data: { id: 1, refreshToken: "r", calendarId: "cal-top3" } });
  });

  it("creates, updates with a checkmark, and deletes an event for a dated task", async () => {
    const t = await newTask({ dueAt: new Date(2026, 9, 6) });
    await syncTasks([t.id]);
    const saved = await prisma.task.findUniqueOrThrow({ where: { id: t.id } });
    expect(g.calls).toEqual([["insert", "Pay rent"]]);
    expect(saved.calendarEventId).toBeTruthy();

    await prisma.task.update({ where: { id: t.id }, data: { completed: true, completedAt: new Date() } });
    await syncTasks([t.id]);
    expect(g.calls[1]).toEqual(["update", saved.calendarEventId, "✅ Pay rent"]);

    await prisma.task.delete({ where: { id: t.id } });
    await deleteEventFor(t.id, saved.calendarEventId);
    expect(g.calls[2]).toEqual(["delete", saved.calendarEventId]);
  });

  it("adds today's Top 3 picks and removes the event when unpinned", async () => {
    const t = await newTask({ title: "Gym" });
    await syncTasks([t.id]);
    expect(g.calls).toEqual([]); // no due date, not pinned: no event

    await prisma.task.update({ where: { id: t.id }, data: { topSlot: 1, topDate: dayKey() } });
    await syncTasks([t.id]);
    expect(g.calls).toEqual([["insert", "⭐ Gym"]]);

    await prisma.task.update({ where: { id: t.id }, data: { topSlot: null, topDate: null } });
    await syncTasks([t.id]);
    expect(g.calls[1][0]).toBe("delete");
    expect((await prisma.task.findUniqueOrThrow({ where: { id: t.id } })).calendarEventId).toBeNull();
  });

  it("does nothing when Google isn't connected", async () => {
    await prisma.googleAccount.deleteMany();
    const t = await newTask({ dueAt: new Date() });
    await syncTasks([t.id]);
    expect(g.calls).toEqual([]);
  });

  it("serialises rapid syncs so a task never gets two events", async () => {
    const t = await newTask({ dueAt: new Date() });
    await Promise.all([syncTasks([t.id]), syncTasks([t.id]), syncTasks([t.id])]);
    expect(g.calls.filter((c) => c[0] === "insert")).toHaveLength(1);
  });
});
