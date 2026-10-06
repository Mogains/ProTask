import { createHash } from "node:crypto";
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
> & { unscheduled?: boolean };

export type EventBody = {
  summary: string;
  description: string;
  start: { date?: string; dateTime?: string; timeZone?: string };
  end: { date?: string; dateTime?: string; timeZone?: string };
  extendedProperties: { private: Record<string, string> };
  transparency: "transparent" | "opaque";
};

/** A task can own one event of each kind. */
export const LINK_KINDS = ["DUE", "PINNED"] as const;
export type LinkKind = (typeof LINK_KINDS)[number];

export const DEFAULT_EVENT_MINUTES = 30;

/**
 * What the "Top 3" calendar should show for a task, by kind. Empty if it should have no events.
 * - DUE: an event on the due date (timed, or all-day for date-only). Marked ⭐ when it is also today's pick.
 * - PINNED: today's Top 3 pick gets an all-day event today, unless its due-date event is already today.
 * - Done tasks keep their events with a ✅ in the title.
 * - Unscheduled tasks (their event was deleted in the calendar) get none until you reschedule them.
 */
export function buildEvents(
  task: EventTask,
  today: string,
  timeZone?: string,
): Partial<Record<LinkKind, EventBody>> {
  if (task.unscheduled) return {};
  const pinnedToday = task.topSlot != null && task.topDate === today;
  const dueDay = task.dueAt ? localDateKey(new Date(task.dueAt)) : null;
  const out: Partial<Record<LinkKind, EventBody>> = {};
  const tz = timeZone ? { timeZone } : {};
  const priority = `Priority: ${task.priority === "HIGH" ? "High" : task.priority === "LOW" ? "Low" : "Med"}`;
  const estimate = task.estimateMinutes ? `Estimate: ${task.estimateMinutes} min` : null;

  if (task.dueAt) {
    const starred = pinnedToday && dueDay === today;
    let start: EventBody["start"];
    let end: EventBody["end"];
    if (task.hasDueTime) {
      const s = new Date(task.dueAt);
      const e = new Date(s.getTime() + (task.estimateMinutes || DEFAULT_EVENT_MINUTES) * 60_000);
      start = { dateTime: s.toISOString(), ...tz };
      end = { dateTime: e.toISOString(), ...tz };
    } else {
      start = { date: dueDay! };
      end = { date: addDays(dueDay!, 1) };
    }
    const meta = [priority, estimate, starred ? `Today's Top 3 #${task.topSlot}` : null].filter(Boolean);
    out.DUE = body(task, "DUE", task.completed ? "✅ " : starred ? "⭐ " : "", meta.join(" · "), start, end);
  }

  if (pinnedToday && dueDay !== today) {
    const meta = [`Today's Top 3 #${task.topSlot}`, dueDay ? `Due ${dueDay}` : null, estimate].filter(Boolean);
    out.PINNED = body(task, "PINNED", task.completed ? "✅ " : "⭐ ", meta.join(" · "), { date: today }, {
      date: addDays(today, 1),
    });
  }
  return out;
}

function body(
  task: EventTask,
  kind: LinkKind,
  prefix: string,
  meta: string,
  start: EventBody["start"],
  end: EventBody["end"],
): EventBody {
  return {
    summary: `${prefix}${task.title}`,
    description: [task.notes, meta, "Synced from Top 3"].filter(Boolean).join("\n\n"),
    start,
    end,
    extendedProperties: { private: { top3TaskId: task.id, top3Kind: kind } },
    // All-day reminders shouldn't block your free/busy time.
    transparency: start.date ? "transparent" : "opaque",
  };
}

/** The one event a task would have had before multiple links (due-date event, else today's pick). */
export function buildEvent(task: EventTask, today: string, timeZone?: string): EventBody | null {
  const e = buildEvents(task, today, timeZone);
  return e.DUE ?? e.PINNED ?? null;
}

type Time = { date?: string | null; dateTime?: string | null };
type EventTimes = { summary?: string | null; start?: Time | null; end?: Time | null };

/** Instant of a dateTime, or the date itself, so "…T14:00:00Z" and "…T16:00:00+02:00" compare equal. */
function when(t?: { date?: string | null; dateTime?: string | null } | null): string {
  if (!t) return "";
  if (t.dateTime) return new Date(t.dateTime).toISOString();
  return t.date ?? "";
}

/**
 * Fingerprint of the fields that sync both ways (title, start, end). Equal hashes mean
 * the two sides agree; a different hash on one side means that side changed since the last sync.
 */
export function contentHash(e: EventTimes): string {
  return createHash("sha256")
    .update(JSON.stringify([e.summary ?? "", when(e.start), when(e.end)]))
    .digest("hex")
    .slice(0, 32);
}
