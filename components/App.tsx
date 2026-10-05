"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  closestCorners,
  DndContext,
  DragOverlay,
  KeyboardSensor,
  MouseSensor,
  TouchSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import { arrayMove, sortableKeyboardCoordinates } from "@dnd-kit/sortable";
import { createTask, deleteTask, reorderList, toggleComplete, updateTask } from "@/app/actions";
import { dailyCompletion } from "@/lib/stats";
import { normalizeInput } from "@/lib/taskInput";
import { isListKind, LISTS, type ListKind, type Snapshot, type Task, type TaskInput } from "@/lib/types";
import { DoneSection } from "./DoneSection";
import { Header } from "./Header";
import { TaskCard } from "./TaskCard";
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

type Order = Record<ListKind, string[]>;

function containerOf(id: string, order: Order): ListKind | null {
  if (id.startsWith("list:")) {
    const l = id.slice(5);
    return isListKind(l) ? l : null;
  }
  return LISTS.find((l) => order[l].includes(id)) ?? null;
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

  // ---------- drag and drop ----------
  const sensors = useSensors(
    useSensor(MouseSensor, { activationConstraint: { distance: 5 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 180, tolerance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );
  const byId = useMemo(() => new Map(tasks.map((t) => [t.id, t])), [tasks]);
  const baseOrder = useMemo<Order>(() => ({ HAVE_TO: lists.HAVE_TO.map((t) => t.id), NICE_TO: lists.NICE_TO.map((t) => t.id) }), [lists]);
  const [preview, setPreview] = useState<Order | null>(null);
  const [activeId, setActiveId] = useState<string | null>(null);
  const order = preview ?? baseOrder;
  const shown = (l: ListKind) => order[l].map((id) => byId.get(id)).filter((t): t is Task => !!t);

  function onDragStart({ active }: DragStartEvent) {
    setActiveId(String(active.id));
    setPreview(baseOrder);
  }

  // Move the dragged card into the other list as soon as it hovers there, so the drop preview is live.
  function onDragOver({ active, over }: DragOverEvent) {
    if (!over) return;
    const aid = String(active.id);
    const oid = String(over.id);
    setPreview((prev) => {
      if (!prev) return prev;
      const from = containerOf(aid, prev);
      const to = containerOf(oid, prev);
      if (!from || !to || from === to) return prev;
      const toIds = [...prev[to]];
      let idx = oid.startsWith("list:") ? toIds.length : toIds.indexOf(oid);
      const r = active.rect.current.translated;
      if (idx >= 0 && r && r.top > over.rect.top + over.rect.height / 2) idx += 1;
      toIds.splice(idx < 0 ? toIds.length : idx, 0, aid);
      return { ...prev, [from]: prev[from].filter((x) => x !== aid), [to]: toIds };
    });
  }

  function onDragEnd({ active, over }: DragEndEvent) {
    const prev = preview;
    setActiveId(null);
    setPreview(null);
    if (!over || !prev) return;
    const aid = String(active.id);
    const oid = String(over.id);
    const to = containerOf(oid, prev);
    if (!to || containerOf(aid, prev) !== to) return;
    let ids = prev[to];
    const oldI = ids.indexOf(aid);
    const newI = oid.startsWith("list:") ? oldI : ids.indexOf(oid);
    if (newI >= 0 && oldI !== newI) ids = arrayMove(ids, oldI, newI);
    const task = byId.get(aid);
    if (!task || (task.list === to && ids.join() === baseOrder[to].join())) return;
    commitOrder(to, ids);
  }

  function commitOrder(list: ListKind, ids: string[]) {
    run(
      (s) => ({
        ...s,
        tasks: s.tasks.map((t) => {
          const i = ids.indexOf(t.id);
          return i < 0 ? t : { ...t, list, position: (i + 1) * 1000 };
        }),
      }),
      () => reorderList(list, ids.filter((id) => !id.startsWith("tmp-"))),
    );
  }

  const activeTask = activeId ? byId.get(activeId) : undefined;

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

      <DndContext
        sensors={sensors}
        collisionDetection={closestCorners}
        onDragStart={onDragStart}
        onDragOver={onDragOver}
        onDragEnd={onDragEnd}
        onDragCancel={() => {
          setActiveId(null);
          setPreview(null);
        }}
      >
        <div className="space-y-6">
          <div className="grid gap-4 md:grid-cols-2">
            {LISTS.map((l) => (
              <TaskList key={l} list={l} tasks={shown(l)} today={today} onToggle={toggle} onEdit={openEdit} onAdd={openNew} />
            ))}
          </div>
          <DoneSection tasks={done} onToggle={toggle} onDelete={remove} />
        </div>
        <DragOverlay dropAnimation={{ duration: 180, easing: "ease-out" }}>
          {activeTask ? <TaskCard task={activeTask} today={today} onToggle={() => {}} onEdit={() => {}} dragging /> : null}
        </DragOverlay>
      </DndContext>

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
