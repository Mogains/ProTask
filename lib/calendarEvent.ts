import { addDays, localDateKey } from "./day";
import type { Task } from "./types";

type EventTask = Pick<
  Task,
  | "id"
  | "title"
  | "notes"
  | "dueAt"
  | "hasDueTime"
  | "priority"
  | "estimateMinutes"
  | "completed"
  | "topSlot"
  | "topDate"
>;

export type EventBody = {
  summary: string;
  description: string;
  start: { date?: string; dateTime?: string; timeZone?: string };
  end: { date?: string; dateTime?: string; timeZone?: string };
  extendedProperties: { private: Record<string, string> };
  transparency: "transparent" | "opaque";
};

export const DEFAULT_EVENT_MINUTES = 30;

/**
 * What the "Top 3" calendar should show for a task, or null if it should have no event.
 * - Tasks with a due date get an event on that date (timed, or all-day for date-only).
 * - Today's Top 3 picks without a due date get an all-day event today.
 * - Done tasks keep their event with a ✅ in the title.
 */
export function buildEvent(task: EventTask, today: string, timeZone?: string): EventBody | null {
  const pinnedToday = task.topSlot != null && task.topDate === today;
  if (!task.dueAt && !pinnedToday) return null;

  const prefix = task.completed ? "✅ " : pinnedToday ? "⭐ " : "";
  const meta = [
    `Priority: ${task.priority === "HIGH" ? "High" : task.priority === "LOW" ? "Low" : "Med"}`,
    task.estimateMinutes ? `Estimate: ${task.estimateMinutes} min` : null,
    pinnedToday ? `Today's Top 3 #${task.topSlot}` : null,
  ].filter(Boolean);

  let start: EventBody["start"];
  let end: EventBody["end"];
  if (task.dueAt && task.hasDueTime) {
    const s = new Date(task.dueAt);
    const e = new Date(s.getTime() + (task.estimateMinutes || DEFAULT_EVENT_MINUTES) * 60_000);
    start = { dateTime: s.toISOString(), ...(timeZone ? { timeZone } : {}) };
    end = { dateTime: e.toISOString(), ...(timeZone ? { timeZone } : {}) };
  } else {
    const day = task.dueAt ? localDateKey(new Date(task.dueAt)) : today;
    start = { date: day };
    end = { date: addDays(day, 1) };
  }

  return {
    summary: `${prefix}${task.title}`,
    description: [task.notes, meta.join(" · "), "Synced from Top 3"].filter(Boolean).join("\n\n"),
    start,
    end,
    extendedProperties: { private: { top3TaskId: task.id } },
    // All-day reminders shouldn't block your free/busy time.
    transparency: start.date ? "transparent" : "opaque",
  };
}
