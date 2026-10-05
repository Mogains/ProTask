"use client";

import { useDroppable } from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";
import type { ReactNode } from "react";
import { SortableTask } from "./SortableTask";
import { LIST_LABEL, type ListKind, type Task } from "@/lib/types";

type Props = {
  list: ListKind;
  tasks: Task[];
  today: string;
  onToggle: (t: Task, completed: boolean) => void;
  onEdit: (t: Task) => void;
  onAdd: (list: ListKind) => void;
  onStar?: (t: Task) => void;
  onActivate?: (t: Task | null) => void;
  headerExtra?: ReactNode;
};

export function TaskList({ list, tasks, today, onToggle, onEdit, onAdd, onStar, onActivate, headerExtra }: Props) {
  const { setNodeRef, isOver } = useDroppable({ id: `list:${list}` });
  return (
    <section
      ref={setNodeRef}
      className={[
        "flex flex-col rounded-2xl border p-3 transition-colors",
        isOver ? "border-amber-400/60 bg-amber-400/5" : "border-zinc-200 bg-zinc-100/60 dark:border-zinc-800 dark:bg-zinc-900/40",
      ].join(" ")}
    >
      <div className="mb-2 flex items-center gap-2 px-1">
        <h2 className="font-semibold">{LIST_LABEL[list]}</h2>
        <span className="text-sm text-zinc-500">{tasks.length}</span>
        <div className="ml-auto">{headerExtra}</div>
      </div>
      <SortableContext items={tasks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
        <div className="flex min-h-16 flex-col gap-2">
          {tasks.map((t) => (
            <SortableTask key={t.id} task={t} today={today} onToggle={onToggle} onEdit={onEdit} onStar={onStar} onActivate={onActivate} />
          ))}
          {!tasks.length && (
            <div className="rounded-xl border border-dashed border-zinc-300 px-3 py-4 text-center text-sm text-zinc-400 dark:border-zinc-700">
              Nothing here. Drag a task in or add one.
            </div>
          )}
        </div>
      </SortableContext>
      <button type="button" onClick={() => onAdd(list)} className="mt-2 rounded-lg px-2 py-2 text-left text-sm text-zinc-500 hover:bg-zinc-500/10">
        + Add task
      </button>
    </section>
  );
}
