import type { Task as DbTask } from "@prisma/client";

export type Task = DbTask;

export const LISTS = ["HAVE_TO", "NICE_TO"] as const;
export type ListKind = (typeof LISTS)[number];
export const LIST_LABEL: Record<ListKind, string> = {
  HAVE_TO: "Have to do",
  NICE_TO: "Nice to do",
};

export const PRIORITIES = ["HIGH", "MED", "LOW"] as const;
export type Priority = (typeof PRIORITIES)[number];
export const PRIORITY_LABEL: Record<Priority, string> = { HIGH: "High", MED: "Med", LOW: "Low" };

export function isListKind(x: unknown): x is ListKind {
  return x === "HAVE_TO" || x === "NICE_TO";
}
export function isPriority(x: unknown): x is Priority {
  return x === "HIGH" || x === "MED" || x === "LOW";
}

/** What the task form sends. dueAt is an ISO string built from local date/time. */
export type TaskInput = {
  title: string;
  notes?: string | null;
  dueAt?: string | null;
  hasDueTime?: boolean;
  priority?: string;
  estimateMinutes?: number | null;
  list?: string;
};

export type Snapshot = {
  tasks: Task[];
  today: string;
  streak: number;
  autoSort: Record<ListKind, boolean>;
  promptDismissed: boolean;
  google: { configured: boolean; connected: boolean; email: string | null; needsReconnect: boolean };
  /** Newest entries of what two-way sync overwrote or removed. */
  syncHistory: SyncHistoryEntry[];
};

export type SyncHistoryEntry = {
  id: string;
  at: Date;
  taskTitle: string;
  reason: string;
  winner: string | null;
  lost: string;
};

export type ActionResult = { snapshot: Snapshot; error?: string };
