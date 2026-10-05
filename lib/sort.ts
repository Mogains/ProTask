import type { Task } from "./types";

type Sortable = Pick<Task, "dueAt" | "hasDueTime" | "priority" | "estimateMinutes" | "position">;

const PRIORITY_RANK: Record<string, number> = { HIGH: 0, MED: 1, LOW: 2 };

/** A date-only due date counts as the end of that day, so timed tasks on the same day come first. */
function dueKey(t: Sortable): number {
  if (!t.dueAt) return Number.POSITIVE_INFINITY;
  const d = new Date(t.dueAt);
  if (!t.hasDueTime) d.setHours(23, 59, 59, 999);
  return d.getTime();
}

/**
 * Auto sort order:
 * 1. due date, soonest first (no due date last)
 * 2. priority, high → low
 * 3. estimated minutes, shortest first (no estimate last)
 * Ties keep the existing manual order.
 */
export function compareTasks(a: Sortable, b: Sortable): number {
  return (
    dueKey(a) - dueKey(b) ||
    (PRIORITY_RANK[a.priority] ?? 1) - (PRIORITY_RANK[b.priority] ?? 1) ||
    (a.estimateMinutes ?? Number.POSITIVE_INFINITY) - (b.estimateMinutes ?? Number.POSITIVE_INFINITY) ||
    a.position - b.position
  );
}

export function sortTasks<T extends Sortable>(tasks: T[]): T[] {
  // Infinity - Infinity is NaN; normalise so the comparator stays consistent.
  return [...tasks].sort((a, b) => compareTasks(a, b) || 0);
}
