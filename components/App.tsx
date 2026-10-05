"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { createTask, deleteTask, toggleComplete, updateTask } from "@/app/actions";
import { dailyCompletion } from "@/lib/stats";
import { normalizeInput } from "@/lib/taskInput";
import { isListKind, LISTS, type ListKind, type Snapshot, type Task, type TaskInput } from "@/lib/types";
import { DoneSection } from "./DoneSection";
import { Header } from "./Header";
import { TaskForm } from "./TaskForm";
import { TaskList } from "./TaskList";
import { Toast } from "./Toast";
import { useStore } from "./useStore";

const patchTask = (id: string, patch: Partial<Task>) => (s: Snapshot): Snapshot => ({
  ...s,
  tasks: s.tasks.map((t) => (t.id === id ? { ...t, ...patch } : t)),
});

function isTyping(e: KeyboardEvent) {
  const el = e.target as HTMLElement | null;
  return !!el && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName));
}

export default function App({ initial }: { initial: Snapshot }) {
  const { snap, run, toast, showToast } = useStore(initial);
  const [form, setForm] = useState<{ task: Task | null; list: ListKind } | null>(null);
  const { tasks, today } = snap;

  const lists = useMemo(() => {
    const out: Record<ListKind, Task[]> = { HAVE_TO: [], NICE_TO: [] };
    for (const t of tasks) if (!t.completed && t.topSlot == null && isListKind(t.list)) out[t.list].push(t);
    for (const l of LISTS) out[l].sort((a, b) => a.position - b.position);
    return out;
  }, [tasks]);

  const done = useMemo(
    () =>
      tasks
        .filter((t) => t.completed && t.topSlot == null)
        .sort((a, b) => +new Date(b.completedAt ?? 0) - +new Date(a.completedAt ?? 0)),
    [tasks],
  );
  const stats = useMemo(() => dailyCompletion(tasks, today), [tasks, today]);

  const toggle = useCallback(
    (task: Task, completed: boolean) =>
      run(patchTask(task.id, { completed, completedAt: completed ? new Date() : null }), () => toggleComplete(task.id, completed)),
    [run],
  );

  const remove = useCallback(
    (task: Task) => {
      setForm(null);
      run((s) => ({ ...s, tasks: s.tasks.filter((t) => t.id !== task.id) }), () => deleteTask(task.id));
      showToast(`Deleted “${task.title}”`);
    },
    [run, showToast],
  );

  function save(input: TaskInput) {
    const existing = form?.task ?? null;
    let data;
    try {
      data = normalizeInput(input);
    } catch (e) {
      return showToast((e as Error).message);
    }
    setForm(null);
    if (existing) {
      const position = data.list === existing.list ? existing.position : Number.MAX_SAFE_INTEGER;
      run(patchTask(existing.id, { ...data, position }), () => updateTask(existing.id, input));
    } else {
      const now = new Date();
      const temp: Task = {
        id: `tmp-${now.getTime()}`,
        ...data,
        completed: false,
        completedAt: null,
        position: Number.MAX_SAFE_INTEGER,
        topSlot: null,
        topDate: null,
        calendarEventId: null,
        syncError: null,
        createdAt: now,
        updatedAt: now,
      };
      run((s) => ({ ...s, tasks: [...s.tasks, temp] }), () => createTask(input));
    }
  }

  const openNew = useCallback((list: ListKind = "HAVE_TO") => setForm({ task: null, list }), []);
  const openEdit = useCallback((task: Task) => {
    if (task.id.startsWith("tmp-")) return;
    setForm({ task, list: task.list as ListKind });
  }, []);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (form || isTyping(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === "n" || e.key === "N") {
        e.preventDefault();
        openNew();
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [form, openNew]);

  return (
    <main className="mx-auto max-w-6xl space-y-6 px-4 py-5 sm:px-6 sm:py-8">
      <Header
        streak={snap.streak}
        {...stats}
        actions={
          <button
            type="button"
            onClick={() => openNew()}
            className="rounded-lg bg-amber-400 px-3 py-1.5 text-sm font-semibold text-zinc-950 hover:bg-amber-300"
            title="New task (N)"
          >
            + New <kbd className="ml-1 hidden rounded bg-black/10 px-1 text-xs sm:inline">N</kbd>
          </button>
        }
      />

      <div className="space-y-6">
        <div className="grid gap-4 md:grid-cols-2">
          {LISTS.map((l) => (
            <TaskList key={l} list={l} tasks={lists[l]} today={today} onToggle={toggle} onEdit={openEdit} onAdd={openNew} />
          ))}
        </div>
        <DoneSection tasks={done} onToggle={toggle} onDelete={remove} />
      </div>

      {form && (
        <TaskForm
          task={form.task}
          defaultList={form.list}
          onSave={save}
          onDelete={form.task ? () => remove(form.task!) : undefined}
          onClose={() => setForm(null)}
        />
      )}
      <Toast toast={toast} />
    </main>
  );
}
