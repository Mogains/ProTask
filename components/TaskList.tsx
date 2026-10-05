"use client";

import { TaskCard } from "./TaskCard";
import { LIST_LABEL, type ListKind, type Task } from "@/lib/types";

type Props = {
  list: ListKind;
  tasks: Task[];
  today: string;
  onToggle: (t: Task, completed: boolean) => void;
  onEdit: (t: Task) => void;
  onAdd: (list: ListKind) => void;
};

export function TaskList({ list, tasks, today, onToggle, onEdit, onAdd }: Props) {
  return (
    <section className="flex flex-col rounded-2xl border border-zinc-200 bg-zinc-100/60 p-3 dark:border-zinc-800 dark:bg-zinc-900/40">
      <div className="mb-2 flex items-center gap-2 px-1">
        <h2 className="font-semibold">{LIST_LABEL[list]}</h2>
        <span className="text-sm text-zinc-500">{tasks.length}</span>
      </div>
      <div className="flex min-h-16 flex-col gap-2">
        {tasks.map((t) => (
          <TaskCard key={t.id} task={t} today={today} onToggle={onToggle} onEdit={onEdit} />
        ))}
      </div>
      <button type="button" onClick={() => onAdd(list)} className="mt-2 rounded-lg px-2 py-2 text-left text-sm text-zinc-500 hover:bg-zinc-500/10">
        + Add task
      </button>
    </section>
  );
}
