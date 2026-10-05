import { describe, expect, it } from "vitest";
import { applyPlan, planTopAssignment, TOP3_FULL_MESSAGE, type Occupant } from "@/lib/top3";

const full: Occupant[] = [
  { slot: 1, taskId: "a" },
  { slot: 2, taskId: "b" },
  { slot: 3, taskId: "c" },
];

describe("Top 3 limit", () => {
  it("fills the first free slot when starring", () => {
    expect(planTopAssignment([], "x")).toEqual({ ok: true, slot: 1, displaced: null });
    expect(planTopAssignment([{ slot: 1, taskId: "a" }, { slot: 3, taskId: "c" }], "x")).toEqual({ ok: true, slot: 2, displaced: null });
  });

  it("refuses a 4th task when all three slots are taken", () => {
    expect(planTopAssignment(full, "d")).toEqual({ ok: false, reason: "full" });
    expect(TOP3_FULL_MESSAGE).toMatch(/full/i);
  });

  it("never ends up with more than three pinned tasks", () => {
    let occ: Occupant[] = [];
    for (const id of ["a", "b", "c", "d", "e"]) {
      const plan = planTopAssignment(occ, id);
      if (plan.ok) occ = applyPlan(occ, id, plan);
    }
    expect(occ.map((o) => o.taskId)).toEqual(["a", "b", "c"]);
    for (const [id, slot] of [["d", 2], ["e", 1], ["a", 3]] as const) {
      const plan = planTopAssignment(occ, id, slot);
      if (plan.ok) occ = applyPlan(occ, id, plan);
      expect(occ.length).toBeLessThanOrEqual(3);
      expect(new Set(occ.map((o) => o.slot)).size).toBe(occ.length);
    }
  });

  it("starring a task that's already pinned keeps its slot", () => {
    expect(planTopAssignment(full, "b")).toEqual({ ok: true, slot: 2, displaced: null });
  });

  it("assigning to an occupied slot sends the old task back to its list", () => {
    const plan = planTopAssignment(full, "d", 2);
    expect(plan).toEqual({ ok: true, slot: 2, displaced: { taskId: "b", toSlot: null } });
    if (plan.ok) expect(applyPlan(full, "d", plan).map((o) => o.taskId)).toEqual(["a", "d", "c"]);
  });

  it("moving between slots swaps the two tasks", () => {
    const plan = planTopAssignment(full, "a", 3);
    expect(plan).toEqual({ ok: true, slot: 3, displaced: { taskId: "c", toSlot: 1 } });
    if (plan.ok) expect(applyPlan(full, "a", plan)).toEqual([{ slot: 1, taskId: "c" }, { slot: 2, taskId: "b" }, { slot: 3, taskId: "a" }]);
  });

  it("rejects slots other than 1, 2 and 3", () => {
    expect(planTopAssignment([], "x", 4)).toEqual({ ok: false, reason: "invalid-slot" });
    expect(planTopAssignment([], "x", 0)).toEqual({ ok: false, reason: "invalid-slot" });
  });
});
