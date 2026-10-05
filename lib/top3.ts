export const SLOTS = [1, 2, 3] as const;
export type SlotNumber = (typeof SLOTS)[number];

export const TOP3_FULL_MESSAGE = "Your Top 3 is full. Finish or remove one first. Three is the magic number 🙂";

export type Occupant = { slot: number; taskId: string };

export type TopPlan =
  | {
      ok: true;
      slot: SlotNumber;
      /** A task already in the requested slot. It swaps into the mover's old slot, or goes back to its list. */
      displaced: { taskId: string; toSlot: SlotNumber | null } | null;
    }
  | { ok: false; reason: "full" | "invalid-slot" };

export function isSlot(n: unknown): n is SlotNumber {
  return n === 1 || n === 2 || n === 3;
}

/**
 * Decide where a task goes in the Top 3. Never produces more than three pinned tasks.
 * - No slot requested (star button): first free slot, or "full" if all three are taken.
 * - Slot requested (drag onto a slot, keys 1/2/3): that slot; its current task is swapped or returned.
 */
export function planTopAssignment(occupants: Occupant[], taskId: string, requested?: number): TopPlan {
  if (requested !== undefined && !isSlot(requested)) return { ok: false, reason: "invalid-slot" };
  const current = occupants.find((o) => o.taskId === taskId);
  const currentSlot = current && isSlot(current.slot) ? current.slot : null;

  if (requested === undefined) {
    if (currentSlot) return { ok: true, slot: currentSlot, displaced: null };
    const taken = new Set(occupants.map((o) => o.slot));
    const free = SLOTS.find((s) => !taken.has(s));
    return free ? { ok: true, slot: free, displaced: null } : { ok: false, reason: "full" };
  }

  const occupant = occupants.find((o) => o.slot === requested);
  if (!occupant || occupant.taskId === taskId) return { ok: true, slot: requested, displaced: null };
  return { ok: true, slot: requested, displaced: { taskId: occupant.taskId, toSlot: currentSlot } };
}

/** Apply a plan to a list of occupants. Used by tests and as a sanity check of the invariant. */
export function applyPlan(occupants: Occupant[], taskId: string, plan: Extract<TopPlan, { ok: true }>): Occupant[] {
  const next = occupants.filter((o) => o.taskId !== taskId && o.taskId !== plan.displaced?.taskId);
  next.push({ slot: plan.slot, taskId });
  if (plan.displaced?.toSlot) next.push({ slot: plan.displaced.toSlot, taskId: plan.displaced.taskId });
  return next.sort((a, b) => a.slot - b.slot);
}
