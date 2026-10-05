"use client";

import { useState } from "react";
import { formatDue, formatMinutes } from "./format";
import type { Task } from "@/lib/types";

const PRIORITY_STYLE: Record<string, string> = {
  HIGH: "bg-rose-500/15 text-rose-600 dark:text-rose-300",
  MED: "bg-amber-500/15 text-amber-700 dark:text-amber-300",
  LOW: "bg-sky-500/15 text-sky-700 dark:text-sky-300",
};

type Props = {
  task: Task;
  today: string;
  onToggle: (task: Task, completed: boolean) => void;
  onEdit: (task: Task) => void;
  onStar?: (task: Task) => void;
  onActivate?: (task: Task) => void;
  /** Keep the card in place after checking (Top 3 slots). */
  stayOnComplete?: boolean;
  starred?: boolean;
  dragging?: boolean;
};

export function TaskCard({ task, today, onToggle, onEdit, onStar, onActivate, stayOnComplete, starred, dragging }: Props) {
  const [completing, setCompleting] = useState(false);
  const checked = task.completed || completing;
  const due = formatDue(task, today);
  const est = formatMinutes(task.estimateMinutes);

  function check() {
    if (task.completed) return onToggle(task, false);
    if (completing) return;
    setCompleting(true);
    // Let the check animation play before the card leaves the list.
    setTimeout(() => {
      onToggle(task, true);
      setCompleting(false);
    }, stayOnComplete ? 150 : 550);
  }

  return (
    <div
      onPointerEnter={() => onActivate?.(task)}
      onFocusCapture={() => onActivate?.(task)}
      className={[
        "group flex items-start gap-3 rounded-xl border px-3 py-2.5 transition-colors",
        "border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900",
        dragging ? "shadow-2xl ring-2 ring-amber-400/60" : "hover:border-zinc-300 dark:hover:border-zinc-700",
        completing && !stayOnComplete ? "animate-complete-out" : "",
      ].join(" ")}
    >
      <button
        type="button"
        role="checkbox"
        aria-checked={checked}
        aria-label={checked ? `Mark "${task.title}" not done` : `Mark "${task.title}" done`}
        onClick={check}
        onPointerDown={(e) => e.stopPropagation()}
        className={[
          "mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 transition-all",
          checked
            ? "animate-check-pop border-emerald-500 bg-emerald-500 text-white"
            : "border-zinc-400 hover:border-emerald-500 dark:border-zinc-600",
        ].join(" ")}
      >
        {checked && (
          <svg viewBox="0 0 16 16" className="h-3 w-3" fill="none" stroke="currentColor" strokeWidth="2.5">
            <path d="M3.5 8.5l3 3 6-7" className="check-path" />
          </svg>
        )}
      </button>

      <button
        type="button"
        onClick={() => onEdit(task)}
        className="min-w-0 flex-1 text-left"
        aria-label={`Edit "${task.title}"`}
      >
        <div className={["break-words text-[15px] leading-snug transition-colors", checked ? "text-zinc-400 line-through dark:text-zinc-500" : ""].join(" ")}>
          {task.title}
        </div>
        {(due || est || task.notes || task.priority !== "MED") && (
          <div className="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-zinc-500 dark:text-zinc-400">
            <span className={`rounded px-1.5 py-0.5 font-medium ${PRIORITY_STYLE[task.priority] ?? ""}`}>
              {task.priority === "HIGH" ? "High" : task.priority === "LOW" ? "Low" : "Med"}
            </span>
            {due && <span className={due.overdue && !task.completed ? "text-rose-500" : ""}>📅 {due.label}</span>}
            {est && <span>⏱ {est}</span>}
            {task.notes && <span title={task.notes}>📝</span>}
            {task.syncError && <span title={task.syncError} className="text-amber-500">⚠ calendar</span>}
          </div>
        )}
      </button>

      {onStar && !task.completed && (
        <button
          type="button"
          onClick={() => onStar(task)}
          onPointerDown={(e) => e.stopPropagation()}
          aria-label={starred ? `Remove "${task.title}" from Top 3` : `Add "${task.title}" to Top 3`}
          title={starred ? "Remove from Top 3" : "Add to Top 3"}
          className={[
            "shrink-0 rounded-md p-1 text-lg leading-none transition",
            starred ? "text-amber-400" : "text-zinc-300 hover:text-amber-400 dark:text-zinc-600",
          ].join(" ")}
        >
          {starred ? "★" : "☆"}
        </button>
      )}
    </div>
  );
}
