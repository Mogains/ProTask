import { isListKind, isPriority, type ListKind, type Priority, type TaskInput } from "./types";

export type NormalizedInput = {
  title: string;
  notes: string | null;
  dueAt: Date | null;
  hasDueTime: boolean;
  priority: Priority;
  estimateMinutes: number | null;
  list: ListKind;
};

/** Validates and cleans form input. Shared by the server and the optimistic client update. */
export function normalizeInput(input: TaskInput): NormalizedInput {
  const title = (input.title ?? "").trim().slice(0, 200);
  if (!title) throw new Error("A task needs a title.");
  const notes = (input.notes ?? "").trim().slice(0, 5000) || null;
  let dueAt: Date | null = input.dueAt ? new Date(input.dueAt) : null;
  if (dueAt && Number.isNaN(dueAt.getTime())) dueAt = null;
  const est = Number(input.estimateMinutes);
  const estimateMinutes =
    input.estimateMinutes != null && Number.isFinite(est) && est > 0 ? Math.min(Math.round(est), 1440) : null;
  return {
    title,
    notes,
    dueAt,
    hasDueTime: !!dueAt && !!input.hasDueTime,
    priority: isPriority(input.priority) ? input.priority : "MED",
    estimateMinutes,
    list: isListKind(input.list) ? input.list : "HAVE_TO",
  };
}
