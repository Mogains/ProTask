"use client";

export function AutoSortToggle({ on, onToggle }: { on: boolean; onToggle: () => void }) {
  return (
    <button
      type="button"
      onClick={onToggle}
      aria-pressed={on}
      title={
        on
          ? "Auto sort: due date, then priority, then shortest first. Dragging a task switches to manual."
          : "Manual order. Click to auto sort by due date, priority, then shortest first."
      }
      className={[
        "flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium transition",
        on
          ? "bg-amber-400/15 text-amber-700 dark:text-amber-300"
          : "border border-zinc-300 text-zinc-500 hover:border-amber-400 hover:text-amber-500 dark:border-zinc-700",
      ].join(" ")}
    >
      <span aria-hidden>{on ? "⚡" : "✋"}</span>
      {on ? "Auto sort" : "Manual · sort"}
    </button>
  );
}
