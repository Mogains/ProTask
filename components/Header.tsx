"use client";

import type { ReactNode } from "react";
import { ThemeToggle } from "./ThemeToggle";

type Props = { streak: number; done: number; total: number; pct: number; actions?: ReactNode };

export function Header({ streak, done, total, pct, actions }: Props) {
  return (
    <header className="flex flex-wrap items-center gap-x-4 gap-y-3">
      <h1 className="text-2xl font-bold tracking-tight">
        Top <span className="text-amber-400">3</span>
      </h1>
      <div
        className="flex items-center gap-1.5 rounded-full bg-orange-500/10 px-3 py-1 text-sm font-medium text-orange-600 dark:text-orange-300"
        title="Days in a row with all Top 3 done"
      >
        🔥 {streak} day{streak === 1 ? "" : "s"}
      </div>
      <div className="flex min-w-40 flex-1 items-center gap-2 sm:max-w-64" title={`${done} of ${total} done today`}>
        <div className="h-2 flex-1 overflow-hidden rounded-full bg-zinc-200 dark:bg-zinc-800">
          <div
            className="h-full rounded-full bg-emerald-500 transition-all duration-500"
            style={{ width: `${pct}%` }}
          />
        </div>
        <span className="text-sm tabular-nums text-zinc-500">{total ? `${pct}% today` : "—"}</span>
      </div>
      <div className="ml-auto flex items-center gap-2">
        {actions}
        <ThemeToggle />
      </div>
    </header>
  );
}
