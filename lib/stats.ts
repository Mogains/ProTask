import { dayKey, localDateKey } from "./day";
import type { Task } from "./types";

/**
 * Today's completion: tasks finished today divided by today's workload
 * (finished today + open tasks that are pinned to the Top 3 or due today/overdue).
 */
export function dailyCompletion(tasks: Task[], today: string) {
  let done = 0;
  let open = 0;
  for (const t of tasks) {
    if (t.completed) {
      if (t.completedAt && dayKey(new Date(t.completedAt)) === today) done++;
    } else if (t.topSlot != null || (t.dueAt && localDateKey(new Date(t.dueAt)) <= today)) {
      open++;
    }
  }
  const total = done + open;
  return { done, total, pct: total ? Math.round((done / total) * 100) : 0 };
}
