"use client";

import { useEffect, useRef, useState } from "react";
import { hhmm, localDateKey } from "@/lib/day";
import { LIST_LABEL, LISTS, PRIORITIES, PRIORITY_LABEL, type ListKind, type Task, type TaskInput } from "@/lib/types";

type Props = {
  task: Task | null;
  defaultList: ListKind;
  onSave: (input: TaskInput) => void;
  onDelete?: () => void;
  onClose: () => void;
};

const field =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-[15px] outline-none focus:border-amber-400 focus:ring-2 focus:ring-amber-400/30 dark:border-zinc-700 dark:bg-zinc-950";

export function TaskForm({ task, defaultList, onSave, onDelete, onClose }: Props) {
  const due = task?.dueAt ? new Date(task.dueAt) : null;
  const [title, setTitle] = useState(task?.title ?? "");
  const [notes, setNotes] = useState(task?.notes ?? "");
  const [list, setList] = useState<string>(task?.list ?? defaultList);
  const [priority, setPriority] = useState<string>(task?.priority ?? "MED");
  const [date, setDate] = useState(due ? localDateKey(due) : "");
  const [time, setTime] = useState(due && task?.hasDueTime ? hhmm(due) : "");
  const [estimate, setEstimate] = useState(task?.estimateMinutes ? String(task.estimateMinutes) : "");
  const titleRef = useRef<HTMLInputElement>(null);

  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useEffect(() => {
    titleRef.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && closeRef.current();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!title.trim()) return titleRef.current?.focus();
    const dueAt = date ? new Date(`${date}T${time || "00:00"}`).toISOString() : null;
    onSave({
      title,
      notes,
      list,
      priority,
      dueAt,
      hasDueTime: !!date && !!time,
      estimateMinutes: estimate ? Number(estimate) : null,
    });
  }

  return (
    <div className="fixed inset-0 z-40 flex items-end justify-center bg-black/50 p-0 backdrop-blur-sm sm:items-center sm:p-4" onMouseDown={onClose}>
      <form
        onSubmit={submit}
        onMouseDown={(e) => e.stopPropagation()}
        className="w-full max-w-lg space-y-4 rounded-t-2xl border border-zinc-200 bg-zinc-50 p-5 shadow-2xl dark:border-zinc-800 dark:bg-zinc-900 sm:rounded-2xl"
      >
        <h2 className="text-lg font-semibold">{task ? "Edit task" : "New task"}</h2>
        <input ref={titleRef} className={field} placeholder="What needs doing?" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} />
        <textarea className={`${field} min-h-20`} placeholder="Notes (optional)" value={notes} onChange={(e) => setNotes(e.target.value)} />

        <Segmented label="List" value={list} onChange={setList} options={LISTS.map((l) => [l, LIST_LABEL[l]])} />
        <Segmented label="Priority" value={priority} onChange={setPriority} options={PRIORITIES.map((p) => [p, PRIORITY_LABEL[p]])} />

        <div className="grid grid-cols-2 gap-3">
          <label className="text-sm text-zinc-500">
            Due date
            <input type="date" className={`${field} mt-1`} value={date} onChange={(e) => setDate(e.target.value)} />
          </label>
          <label className="text-sm text-zinc-500">
            Time (optional)
            <input type="time" className={`${field} mt-1`} value={time} disabled={!date} onChange={(e) => setTime(e.target.value)} />
          </label>
        </div>

        <label className="block text-sm text-zinc-500">
          Estimated minutes
          <div className="mt-1 flex gap-2">
            <input type="number" min={1} max={1440} inputMode="numeric" className={field} placeholder="e.g. 25" value={estimate} onChange={(e) => setEstimate(e.target.value)} />
            {[15, 30, 60].map((m) => (
              <button key={m} type="button" onClick={() => setEstimate(String(m))} className="rounded-lg border border-zinc-300 px-3 text-sm dark:border-zinc-700">
                {m}
              </button>
            ))}
          </div>
        </label>

        <div className="flex items-center gap-2 pt-1">
          {onDelete && (
            <button type="button" onClick={onDelete} className="rounded-lg px-3 py-2 text-sm text-rose-500 hover:bg-rose-500/10">
              Delete
            </button>
          )}
          <div className="flex-1" />
          <button type="button" onClick={onClose} className="rounded-lg px-4 py-2 text-sm text-zinc-500 hover:bg-zinc-500/10">
            Cancel
          </button>
          <button type="submit" className="rounded-lg bg-amber-400 px-4 py-2 text-sm font-semibold text-zinc-950 hover:bg-amber-300">
            {task ? "Save" : "Add task"}
          </button>
        </div>
      </form>
    </div>
  );
}

function Segmented({ label, value, onChange, options }: { label: string; value: string; onChange: (v: string) => void; options: [string, string][] }) {
  return (
    <div>
      <div className="mb-1 text-sm text-zinc-500">{label}</div>
      <div className="flex rounded-lg border border-zinc-300 p-0.5 dark:border-zinc-700">
        {options.map(([v, l]) => (
          <button
            key={v}
            type="button"
            onClick={() => onChange(v)}
            className={`flex-1 rounded-md px-3 py-1.5 text-sm transition ${value === v ? "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900" : "text-zinc-500"}`}
          >
            {l}
          </button>
        ))}
      </div>
    </div>
  );
}
