import { contentHash, DEFAULT_EVENT_MINUTES, type EventBody, type LinkKind } from "./calendarEvent";
import { parseKey } from "./day";

/** The parts of a Google event that two-way sync reads. */
export type RemoteEvent = {
  id?: string | null;
  etag?: string | null;
  updated?: string | null;
  status?: string | null;
  summary?: string | null;
  start?: { date?: string | null; dateTime?: string | null } | null;
  end?: { date?: string | null; dateTime?: string | null } | null;
};

export type LinkSnapshot = { kind: string; etag: string | null; contentHash: string | null };

export type Decision =
  | "unchanged" // the calendar version is what we last synced
  | "converged" // both sides changed to the same thing
  | "pull" // only the calendar changed: apply it to the task
  | "remote-wins" // both changed, the calendar edit is newer
  | "local-wins"; // both changed, the task edit is newer

/**
 * Who changed what since the last sync, judged by content hashes (title, start, end):
 * the link remembers the hash both sides agreed on. Only when both moved away from it
 * do the modified times decide, and the newest edit wins.
 */
export function decide(
  link: LinkSnapshot,
  remote: RemoteEvent,
  local: EventBody | null | undefined,
  taskUpdatedAt: Date,
): Decision {
  const remoteHash = contentHash(remote);
  const localHash = local ? contentHash(local) : null;
  if (remoteHash === link.contentHash) return "unchanged";
  if (localHash === remoteHash) return "converged";
  if (localHash === link.contentHash || localHash === null) return "pull";
  const remoteTime = remote.updated ? Date.parse(remote.updated) : 0;
  return remoteTime > taskUpdatedAt.getTime() ? "remote-wins" : "local-wins";
}

/** ProTask's own title markers, which are not part of the task title. */
export function titleFromSummary(summary: string | null | undefined): string | null {
  const t = (summary ?? "").replace(/^(✅|⭐)\s*/u, "").trim();
  return t ? t.slice(0, 500) : null;
}

type TaskTimes = { title: string; dueAt: Date | null; hasDueTime: boolean; estimateMinutes: number | null };

/**
 * The task fields a calendar edit changes.
 * - DUE events: title, date or time, and the length (as the estimate) for timed events.
 * - PINNED events: the title only. The day of a Top 3 event follows the Top 3, so a move is
 *   reported back via `pinnedMoved` and the event goes back to its day (logged in sync history).
 */
export function remotePatch(
  kind: LinkKind | string,
  ev: RemoteEvent,
  task: TaskTimes,
  pinDay: string | null,
): { patch: Partial<TaskTimes>; pinnedMoved: boolean } {
  const patch: Partial<TaskTimes> = {};
  const title = titleFromSummary(ev.summary);
  if (title && title !== task.title) patch.title = title;

  if (kind === "PINNED") {
    const day = ev.start?.date ?? (ev.start?.dateTime ? ev.start.dateTime.slice(0, 10) : null);
    return { patch, pinnedMoved: !!pinDay && !!day && day !== pinDay };
  }

  if (ev.start?.date) {
    const dueAt = parseKey(ev.start.date);
    if (task.hasDueTime || task.dueAt?.getTime() !== dueAt.getTime()) {
      patch.dueAt = dueAt;
      patch.hasDueTime = false;
    }
  } else if (ev.start?.dateTime) {
    const start = new Date(ev.start.dateTime);
    if (!task.hasDueTime || task.dueAt?.getTime() !== start.getTime()) {
      patch.dueAt = start;
      patch.hasDueTime = true;
    }
    if (ev.end?.dateTime) {
      const minutes = Math.round((Date.parse(ev.end.dateTime) - start.getTime()) / 60_000);
      if (minutes > 0 && minutes <= 24 * 60 && minutes !== (task.estimateMinutes || DEFAULT_EVENT_MINUTES)) {
        patch.estimateMinutes = minutes;
      }
    }
  }
  return { patch, pinnedMoved: false };
}

/** A small, human-readable copy of an event version for the sync history. */
export function versionOf(e: { summary?: string | null; start?: RemoteEvent["start"]; end?: RemoteEvent["end"] } | null | undefined) {
  if (!e) return JSON.stringify(null);
  return JSON.stringify({
    title: e.summary ?? "",
    start: e.start?.dateTime ?? e.start?.date ?? null,
    end: e.end?.dateTime ?? e.end?.date ?? null,
  });
}
