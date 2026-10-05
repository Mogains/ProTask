import { describe, expect, it } from "vitest";
import { compareTasks, sortTasks } from "@/lib/sort";

type T = {
  id: string;
  dueAt: Date | null;
  hasDueTime: boolean;
  priority: string;
  estimateMinutes: number | null;
  position: number;
};

let pos = 0;
const task = (id: string, o: Partial<T> = {}): T => ({
  id,
  dueAt: null,
  hasDueTime: false,
  priority: "MED",
  estimateMinutes: null,
  position: (pos += 1000),
  ...o,
});
const ids = (ts: T[]) => sortTasks(ts).map((t) => t.id);

describe("auto sort", () => {
  it("puts the soonest due date first and undated tasks last", () => {
    const ts = [
      task("none"),
      task("later", { dueAt: new Date(2026, 9, 10) }),
      task("sooner", { dueAt: new Date(2026, 9, 6) }),
    ];
    expect(ids(ts)).toEqual(["sooner", "later", "none"]);
  });

  it("breaks due-date ties by priority, high first", () => {
    const d = new Date(2026, 9, 6);
    const ts = [task("low", { dueAt: d, priority: "LOW" }), task("high", { dueAt: d, priority: "HIGH" }), task("med", { dueAt: d })];
    expect(ids(ts)).toEqual(["high", "med", "low"]);
  });

  it("breaks priority ties by shortest estimate, unestimated last", () => {
    const ts = [task("none"), task("long", { estimateMinutes: 90 }), task("short", { estimateMinutes: 10 })];
    expect(ids(ts)).toEqual(["short", "long", "none"]);
  });

  it("orders due date before priority before estimate", () => {
    const ts = [
      task("high-undated-short", { priority: "HIGH", estimateMinutes: 5 }),
      task("low-due", { priority: "LOW", dueAt: new Date(2026, 9, 7), estimateMinutes: 120 }),
    ];
    expect(ids(ts)).toEqual(["low-due", "high-undated-short"]);
  });

  it("puts a timed task before a date-only task on the same day", () => {
    const ts = [
      task("all-day", { dueAt: new Date(2026, 9, 6) }),
      task("at-3pm", { dueAt: new Date(2026, 9, 6, 15), hasDueTime: true }),
    ];
    expect(ids(ts)).toEqual(["at-3pm", "all-day"]);
  });

  it("keeps manual order for complete ties and does not mutate input", () => {
    const ts = [task("a"), task("b"), task("c")];
    const copy = [...ts];
    expect(ids(ts)).toEqual(["a", "b", "c"]);
    expect(ts).toEqual(copy);
    expect(compareTasks(ts[0], ts[0])).toBe(0);
  });
});
