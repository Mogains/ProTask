"use client";

import type { Task } from "@/lib/types";

type Props = { tasks: Task[]; onToggle: (t: Task, completed: boolean) => void; onDelete: (t: Task) => void };

export function DoneSection({ tasks, onToggle, onDelete }: Props) {
  if (!tasks.length) return null;
  return (
    <details className="group rounded-xl border border-zinc-200 dark:border-zinc-800">
      <summary className="flex cursor-pointer list-none items-center gap-2 px-4 py-3 text-sm font-medium text-zinc-500">
        <span className="transition group-open:rotate-90">▸</span> Done ({tasks.length})
      </summary>
      <ul className="space-y-1 px-3 pb-3">
        {tasks.slice(0, 100).map((t) => (
          <li key={t.id} className="flex items-center gap-3 rounded-lg px-2 py-1.5 hover:bg-zinc-500/5">
            <button
              type="button"
              role="checkbox"
              aria-checked
              aria-label={`Mark "${t.title}" not done`}
              onClick={() => onToggle(t, false)}
              className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-emerald-500 text-xs text-white"
            >
              ✓
            </button>
            <span className="flex-1 text-sm text-zinc-500 line-through">{t.title}</span>
            <button type="button" onClick={() => onDelete(t)} className="text-xs text-zinc-400 hover:text-rose-500" aria-label={`Delete "${t.title}"`}>
              Delete
            </button>
          </li>
        ))}
      </ul>
    </details>
  );
}
