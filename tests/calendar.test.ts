import { describe, expect, it } from "vitest";
import { buildEvent } from "@/lib/calendarEvent";
import { freeSlots, type CalEvent } from "@/lib/freeTime";

const base = {
  id: "t1",
  title: "Write report",
  notes: null,
  dueAt: null,
  hasDueTime: false,
  priority: "MED",
  estimateMinutes: null,
  completed: false,
  topSlot: null,
  topDate: null,
};
const today = "2026-10-05";

describe("buildEvent", () => {
  it("skips tasks with no due date that aren't in today's Top 3", () => {
    expect(buildEvent(base, today)).toBeNull();
    expect(buildEvent({ ...base, topSlot: 1, topDate: "2026-10-04" }, today)).toBeNull();
  });

  it("makes an all-day event today for a Top 3 pick without a time", () => {
    const e = buildEvent({ ...base, topSlot: 2, topDate: today }, today)!;
    expect(e.start).toEqual({ date: "2026-10-05" });
    expect(e.end).toEqual({ date: "2026-10-06" });
    expect(e.summary).toBe("⭐ Write report");
  });

  it("uses due time and estimate for timed events", () => {
    const due = new Date(2026, 9, 6, 14, 0);
    const e = buildEvent({ ...base, dueAt: due, hasDueTime: true, estimateMinutes: 45 }, today)!;
    expect(new Date(e.start.dateTime!).getTime()).toBe(due.getTime());
    expect(new Date(e.end.dateTime!).getTime() - due.getTime()).toBe(45 * 60_000);
  });

  it("adds a checkmark when the task is done", () => {
    expect(buildEvent({ ...base, dueAt: new Date(2026, 9, 6), completed: true }, today)!.summary).toBe(
      "✅ Write report",
    );
  });
});

describe("freeSlots", () => {
  const d = (h: number, m = 0) => new Date(2026, 9, 5, h, m);
  const ev = (s: Date, e: Date, allDay = false): CalEvent => ({
    id: String(+s),
    title: "x",
    start: s.toISOString(),
    end: e.toISOString(),
    allDay,
  });

  it("finds gaps between overlapping events and ignores all-day ones", () => {
    const events = [ev(d(9), d(10)), ev(d(9, 30), d(11)), ev(d(13), d(14)), ev(d(0), d(23, 59), true)];
    const gaps = freeSlots(events, d(8), d(18), d(7));
    expect(gaps.map((g) => [g.start.getHours(), g.end.getHours()])).toEqual([
      [8, 9],
      [11, 13],
      [14, 18],
    ]);
  });

  it("starts from now and drops tiny gaps", () => {
    const gaps = freeSlots([ev(d(12, 10), d(15))], d(8), d(18), d(12));
    expect(gaps.map((g) => g.minutes)).toEqual([180]);
  });
});
