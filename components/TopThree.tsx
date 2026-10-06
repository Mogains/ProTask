"use client";

import { useDraggable, useDroppable } from "@dnd-kit/core";
import { TaskCard } from "./TaskCard";
import { SLOTS, type SlotNumber } from "@/lib/top3";
import type { Task } from "@/lib/types";

type CardHandlers = {
  today: string;
  onToggle: (t: Task, completed: boolean) => void;
  onEdit: (t: Task) => void;
  onUnpin: (t: Task) => void;
  onActivate: (t: Task | null) => void;
};

type Props = CardHandlers & {
  bySlot: Partial<Record<SlotNumber, Task>>;
  showPrompt: boolean;
  onDismissPrompt: () => void;
  allDone: boolean;
  unscheduled: Task[];
  onPutBack: (t: Task) => void;
};

export function TopThree({ bySlot, showPrompt, onDismissPrompt, allDone, unscheduled, onPutBack, ...handlers }: Props) {
  const filled = SLOTS.filter((s) => bySlot[s]).length;
  const doneCount = SLOTS.filter((s) => bySlot[s]?.completed).length;
  return (
    <section
      className={[
        "rounded-2xl border p-4 transition-colors sm:p-5",
        allDone
          ? "border-emerald-500/50 bg-emerald-500/5"
          : "border-amber-400/40 bg-gradient-to-br from-amber-400/10 via-transparent to-transparent",
      ].join(" ")}
      aria-label="Today's Top 3"
    >
      <div className="mb-3 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <h2 className="text-lg font-semibold">Today’s Top 3</h2>
        <span className="text-sm text-zinc-500">
          {allDone
            ? "All done. Enjoy the rest of your day 🎉"
            : filled
              ? `${doneCount}/${filled} done`
              : "Pick three things that matter today"}
        </span>
      </div>

      {showPrompt && (
        <div className="mb-3 flex flex-wrap items-center gap-3 rounded-xl bg-amber-400/15 px-4 py-3 text-sm">
          <span className="flex-1">
            ☀️ <strong>New day!</strong> Pick your Top 3: tap ☆ on a task, drag it into a slot, or hover it and press 1,
            2 or 3. Yesterday’s unfinished picks are back in their lists.
          </span>
          <button
            type="button"
            onClick={onDismissPrompt}
            className="rounded-lg px-2 py-1 text-zinc-500 hover:bg-black/5 dark:hover:bg-white/5"
          >
            Not now
          </button>
        </div>
      )}

      <div className="grid gap-3 md:grid-cols-3">
        {SLOTS.map((n) => (
          <Slot key={n} n={n} task={bySlot[n]} glow={showPrompt} {...handlers} />
        ))}
      </div>

      {unscheduled.length > 0 && (
        <div className="mt-4">
          <h3 className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-zinc-500">
            Removed from your calendar
          </h3>
          <ul className="space-y-1.5">
            {unscheduled.map((t) => (
              <li key={t.id} className="flex items-center gap-2">
                <div className="min-w-0 flex-1">
                  <TaskCard
                    task={t}
                    today={handlers.today}
                    onToggle={handlers.onToggle}
                    onEdit={handlers.onEdit}
                    onActivate={handlers.onActivate}
                  />
                </div>
                <button
                  type="button"
                  onClick={() => onPutBack(t)}
                  className="shrink-0 rounded-lg px-2 py-1 text-sm text-zinc-500 hover:bg-black/5 hover:text-zinc-900 dark:hover:bg-white/5 dark:hover:text-zinc-100"
                  title="Create its calendar event again"
                >
                  Put back
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}

function Slot({ n, task, glow, ...h }: CardHandlers & { n: SlotNumber; task?: Task; glow: boolean }) {
  const { setNodeRef, isOver } = useDroppable({ id: `slot:${n}` });
  return (
    <div
      ref={setNodeRef}
      className={[
        "relative min-h-[4.5rem] rounded-xl transition",
        isOver ? "ring-2 ring-amber-400" : "",
        !task && glow ? "animate-slot-glow" : "",
      ].join(" ")}
    >
      <span className="absolute -left-1.5 -top-1.5 z-10 flex h-5 w-5 items-center justify-center rounded-full bg-amber-400 text-[11px] font-bold text-zinc-950">
        {n}
      </span>
      {task ? (
        <PinnedTask task={task} {...h} />
      ) : (
        <div className="flex h-full min-h-[4.5rem] items-center justify-center rounded-xl border-2 border-dashed border-amber-400/30 px-3 text-center text-sm text-zinc-400">
          Drop a task here or press <kbd className="mx-1 rounded bg-zinc-500/15 px-1.5">{n}</kbd>
        </div>
      )}
    </div>
  );
}

function PinnedTask({ task, today, onToggle, onEdit, onUnpin, onActivate }: CardHandlers & { task: Task }) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: task.id });
  return (
    <div
      ref={setNodeRef}
      {...attributes}
      {...listeners}
      onPointerLeave={() => onActivate(null)}
      aria-label={`Drag “${task.title}”`}
      aria-roledescription="draggable task"
      className={`touch-manipulation outline-none focus-visible:rounded-xl focus-visible:ring-2 focus-visible:ring-amber-400 ${isDragging ? "opacity-30" : ""}`}
    >
      <TaskCard
        task={task}
        today={today}
        onToggle={onToggle}
        onEdit={onEdit}
        onStar={onUnpin}
        onActivate={onActivate}
        starred
        stayOnComplete
      />
    </div>
  );
}
