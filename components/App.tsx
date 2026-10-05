"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  closestCorners,
  DndContext,
  DragOverlay,
  KeyboardSensor,
  MouseSensor,
  pointerWithin,
  TouchSensor,
  useSensor,
  useSensors,
  type CollisionDetection,
  type DragEndEvent,
  type DragOverEvent,
  type DragStartEvent,
} from "@dnd-kit/core";
import { arrayMove, sortableKeyboardCoordinates } from "@dnd-kit/sortable";
import {
  assignTop,
  createTask,
  deleteTask,
  disconnectGoogle,
  dismissPrompt,
  getState,
  removeTop,
  reorderList,
  setAutoSort,
  toggleComplete,
  updateTask,
} from "@/app/actions";
import { dayKey } from "@/lib/day";
import { sortTasks } from "@/lib/sort";
import { dailyCompletion } from "@/lib/stats";
import { normalizeInput } from "@/lib/taskInput";
import { isSlot, planTopAssignment, SLOTS, TOP3_FULL_MESSAGE, type SlotNumber } from "@/lib/top3";
import { isListKind, LISTS, type ListKind, type Snapshot, type Task, type TaskInput } from "@/lib/types";
import { AutoSortToggle } from "./AutoSortToggle";
import { CalendarSidebar } from "./CalendarSidebar";
import { Confetti } from "./Confetti";
import { DoneSection } from "./DoneSection";
import { Header } from "./Header";
import { TaskCard } from "./TaskCard";
import { TaskForm } from "./TaskForm";
import { TaskList } from "./TaskList";
import { Toast } from "./Toast";
import { TopThree } from "./TopThree";
import { useStore } from "./useStore";

type Order = Record<ListKind, string[]>;

const patchTask =
  (id: string, patch: Partial<Task>) =>
  (s: Snapshot): Snapshot => ({
    ...s,
    tasks: s.tasks.map((t) => (t.id === id ? { ...t, ...patch } : t)),
  });

function isTyping(e: KeyboardEvent) {
  const el = e.target as HTMLElement | null;
  return !!el && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName));
}

function containerOf(id: string, order: Order): ListKind | null {
  if (id.startsWith("list:")) {
    const l = id.slice(5);
    return isListKind(l) ? l : null;
  }
  return LISTS.find((l) => order[l].includes(id)) ?? null;
}

/** Top 3 slots win when the pointer is inside one; otherwise use the sortable-friendly closestCorners. */
const collisionDetection: CollisionDetection = (args) => {
  const isSlotId = (id: unknown) => String(id).startsWith("slot:");
  const slotHits = pointerWithin({
    ...args,
    droppableContainers: args.droppableContainers.filter((c) => isSlotId(c.id)),
  });
  if (slotHits.length) return slotHits;
  return closestCorners({ ...args, droppableContainers: args.droppableContainers.filter((c) => !isSlotId(c.id)) });
};

export default function App({ initial }: { initial: Snapshot }) {
  const { snap, setSnap, run, toast, showToast } = useStore(initial);
  const [form, setForm] = useState<{ task: Task | null; list: ListKind } | null>(null);
  const { tasks, today } = snap;

  // ---------- derived state ----------
  const lists = useMemo(() => {
    const out: Record<ListKind, Task[]> = { HAVE_TO: [], NICE_TO: [] };
    for (const t of tasks) if (!t.completed && t.topSlot == null && isListKind(t.list)) out[t.list].push(t);
    for (const l of LISTS)
      out[l] = snap.autoSort[l] ? sortTasks(out[l]) : out[l].sort((a, b) => a.position - b.position);
    return out;
  }, [tasks, snap.autoSort]);

  const bySlot = useMemo(() => {
    const out: Partial<Record<SlotNumber, Task>> = {};
    for (const t of tasks) if (isSlot(t.topSlot)) out[t.topSlot] = t;
    return out;
  }, [tasks]);
  const pinned = SLOTS.map((s) => bySlot[s]).filter((t): t is Task => !!t);
  const allDone = pinned.length === 3 && pinned.every((t) => t.completed);
  const showPrompt = !snap.promptDismissed && pinned.length === 0 && lists.HAVE_TO.length + lists.NICE_TO.length > 0;

  const done = useMemo(
    () =>
      tasks
        .filter((t) => t.completed && t.topSlot == null)
        .sort((a, b) => +new Date(b.completedAt ?? 0) - +new Date(a.completedAt ?? 0)),
    [tasks],
  );
  const stats = useMemo(() => dailyCompletion(tasks, today), [tasks, today]);
  const byId = useMemo(() => new Map(tasks.map((t) => [t.id, t])), [tasks]);

  // ---------- task actions ----------
  const toggle = useCallback(
    (task: Task, completed: boolean) =>
      run(patchTask(task.id, { completed, completedAt: completed ? new Date() : null }), () =>
        toggleComplete(task.id, completed),
      ),
    [run],
  );

  const remove = useCallback(
    (task: Task) => {
      setForm(null);
      run(
        (s) => ({ ...s, tasks: s.tasks.filter((t) => t.id !== task.id) }),
        () => deleteTask(task.id),
      );
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
      run(
        (s) => ({ ...s, tasks: [...s.tasks, temp] }),
        () => createTask(input),
      );
    }
  }

  // ---------- Top 3 ----------
  const pin = useCallback(
    (task: Task, slot?: number) => {
      if (task.id.startsWith("tmp-")) return;
      if (task.completed) return showToast("That one's already done ✓");
      const occupants = tasks.filter((t) => t.topSlot != null).map((t) => ({ slot: t.topSlot!, taskId: t.id }));
      const plan = planTopAssignment(occupants, task.id, slot);
      if (!plan.ok) return showToast(plan.reason === "full" ? TOP3_FULL_MESSAGE : "Pick slot 1, 2 or 3.");
      run(
        (s) => ({
          ...s,
          tasks: s.tasks.map((t) => {
            if (t.id === task.id) return { ...t, topSlot: plan.slot, topDate: s.today };
            if (t.id === plan.displaced?.taskId) {
              const to = plan.displaced.toSlot;
              return { ...t, topSlot: to, topDate: to ? s.today : null };
            }
            return t;
          }),
        }),
        () => assignTop(task.id, slot),
      );
    },
    [tasks, run, showToast],
  );

  const unpin = useCallback(
    (task: Task) => run(patchTask(task.id, { topSlot: null, topDate: null }), () => removeTop(task.id)),
    [run],
  );

  // Celebrate when the third one gets checked (not on page load).
  const [celebrating, setCelebrating] = useState(false);
  const wasAllDone = useRef(allDone);
  useEffect(() => {
    if (allDone && !wasAllDone.current) {
      setCelebrating(true);
      showToast("All three done. That’s a win! 🎉");
      const t = setTimeout(() => setCelebrating(false), 3500);
      wasAllDone.current = allDone;
      return () => clearTimeout(t);
    }
    wasAllDone.current = allDone;
  }, [allDone, showToast]);

  // New day while the app is open (or resumed on the phone): reload so the morning reset runs.
  useEffect(() => {
    const check = () => {
      if (document.visibilityState === "visible" && dayKey() !== snap.today)
        getState()
          .then(setSnap)
          .catch(() => {});
    };
    const id = setInterval(check, 60_000);
    document.addEventListener("visibilitychange", check);
    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", check);
    };
  }, [snap.today, setSnap]);

  // Result of the Google OAuth redirect (?google=...).
  useEffect(() => {
    const url = new URL(window.location.href);
    const g = url.searchParams.get("google");
    if (!g) return;
    const messages: Record<string, string> = {
      connected: "Google Calendar connected. Syncing your tasks to the “Top 3” calendar.",
      denied: "Google Calendar wasn't connected.",
      "not-configured": "Add GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET to .env first. See the README.",
      "bad-state": "That sign-in link expired. Please try connecting again.",
      error: "Couldn't connect Google Calendar. Check the server log.",
    };
    showToast(messages[g] ?? "Google Calendar: " + g);
    url.searchParams.delete("google");
    window.history.replaceState(null, "", url.pathname + url.search);
  }, [showToast]);

  // ---------- drag and drop ----------
  const sensors = useSensors(
    useSensor(MouseSensor, { activationConstraint: { distance: 5 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 180, tolerance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );
  const baseOrder = useMemo<Order>(
    () => ({ HAVE_TO: lists.HAVE_TO.map((t) => t.id), NICE_TO: lists.NICE_TO.map((t) => t.id) }),
    [lists],
  );
  const [preview, setPreview] = useState<Order | null>(null);
  const [activeId, setActiveId] = useState<string | null>(null);
  const order = preview ?? baseOrder;
  const shown = (l: ListKind) => order[l].map((id) => byId.get(id)).filter((t): t is Task => !!t);

  function onDragStart({ active }: DragStartEvent) {
    setActiveId(String(active.id));
    setPreview(baseOrder);
  }

  // Move the dragged card into the hovered list right away, so the drop preview is live.
  function onDragOver({ active, over }: DragOverEvent) {
    if (!over) return;
    const aid = String(active.id);
    const oid = String(over.id);
    setPreview((prev) => {
      if (!prev) return prev;
      const from = containerOf(aid, prev); // null when dragging out of a Top 3 slot
      const to = containerOf(oid, prev);
      if (!to || from === to) return prev;
      const toIds = [...prev[to]];
      let idx = oid.startsWith("list:") ? toIds.length : toIds.indexOf(oid);
      const r = active.rect.current.translated;
      if (idx >= 0 && r && r.top > over.rect.top + over.rect.height / 2) idx += 1;
      toIds.splice(idx < 0 ? toIds.length : idx, 0, aid);
      return from ? { ...prev, [from]: prev[from].filter((x) => x !== aid), [to]: toIds } : { ...prev, [to]: toIds };
    });
  }

  function onDragEnd({ active, over }: DragEndEvent) {
    const prev = preview;
    setActiveId(null);
    setPreview(null);
    if (!over || !prev) return;
    const aid = String(active.id);
    const oid = String(over.id);
    const task = byId.get(aid);
    if (!task) return;

    if (oid.startsWith("slot:")) return pin(task, Number(oid.slice(5)));

    const to = containerOf(oid, prev);
    if (!to) return;
    let ids = prev[to];
    if (!ids.includes(aid)) ids = [...ids, aid];
    const oldI = ids.indexOf(aid);
    const newI = oid.startsWith("list:") ? oldI : ids.indexOf(oid);
    if (newI >= 0 && oldI !== newI) ids = arrayMove(ids, oldI, newI);
    if (task.topSlot == null && task.list === to && ids.join() === baseOrder[to].join()) return;
    commitOrder(to, ids);
  }

  function commitOrder(list: ListKind, ids: string[]) {
    run(
      (s) => ({
        ...s,
        autoSort: { ...s.autoSort, [list]: false },
        tasks: s.tasks.map((t) => {
          const i = ids.indexOf(t.id);
          return i < 0 ? t : { ...t, list, position: (i + 1) * 1000, topSlot: null, topDate: null };
        }),
      }),
      () =>
        reorderList(
          list,
          ids.filter((id) => !id.startsWith("tmp-")),
        ),
    );
  }

  function toggleAutoSort(list: ListKind) {
    const on = !snap.autoSort[list];
    const ids = sortTasks(lists[list]).map((t) => t.id);
    run(
      (s) => ({
        ...s,
        autoSort: { ...s.autoSort, [list]: on },
        tasks: s.tasks.map((t) => {
          const i = ids.indexOf(t.id);
          return i < 0 ? t : { ...t, position: (i + 1) * 1000 };
        }),
      }),
      () => setAutoSort(list, on),
    );
  }

  const activeTask = activeId ? byId.get(activeId) : undefined;

  // ---------- keyboard ----------
  const openNew = useCallback((list: ListKind = "HAVE_TO") => setForm({ task: null, list }), []);
  const openEdit = useCallback((task: Task) => {
    if (task.id.startsWith("tmp-")) return;
    setForm({ task, list: task.list as ListKind });
  }, []);

  // The task under the pointer or keyboard focus is the target of the 1/2/3 shortcuts.
  const hovered = useRef<string | null>(null);
  const onActivate = useCallback((t: Task | null) => {
    hovered.current = t?.id ?? null;
  }, []);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (form || isTyping(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === "n" || e.key === "N") {
        e.preventDefault();
        openNew();
      } else if (e.key === "1" || e.key === "2" || e.key === "3") {
        const task = hovered.current ? byId.get(hovered.current) : undefined;
        if (!task) return showToast("Hover over a task (or tab to it), then press 1, 2 or 3.");
        e.preventDefault();
        pin(task, Number(e.key));
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [form, openNew, byId, pin, showToast]);

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
        id="top3-dnd"
        sensors={sensors}
        collisionDetection={collisionDetection}
        onDragStart={onDragStart}
        onDragOver={onDragOver}
        onDragEnd={onDragEnd}
        onDragCancel={() => {
          setActiveId(null);
          setPreview(null);
        }}
      >
        <div className="space-y-6">
          <TopThree
            bySlot={bySlot}
            today={today}
            allDone={allDone}
            showPrompt={showPrompt}
            onDismissPrompt={() => run((s) => ({ ...s, promptDismissed: true }), dismissPrompt)}
            onToggle={toggle}
            onEdit={openEdit}
            onUnpin={unpin}
            onActivate={onActivate}
          />
          <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_300px]">
            <div className="min-w-0 space-y-6">
              <div className="grid gap-4 md:grid-cols-2">
                {LISTS.map((l) => (
                  <TaskList
                    key={l}
                    list={l}
                    tasks={shown(l)}
                    today={today}
                    onToggle={toggle}
                    onEdit={openEdit}
                    onAdd={openNew}
                    onStar={(t) => pin(t)}
                    onActivate={onActivate}
                    headerExtra={<AutoSortToggle on={snap.autoSort[l]} onToggle={() => toggleAutoSort(l)} />}
                  />
                ))}
              </div>
              <DoneSection tasks={done} onToggle={toggle} onDelete={remove} />
            </div>
            <div className="lg:sticky lg:top-6 lg:self-start">
              <CalendarSidebar
                {...snap.google}
                onDisconnect={() =>
                  run((s) => ({ ...s, google: { ...s.google, connected: false, email: null } }), disconnectGoogle)
                }
              />
            </div>
          </div>
        </div>
        <DragOverlay dropAnimation={{ duration: 180, easing: "ease-out" }}>
          {activeTask ? (
            <TaskCard task={activeTask} today={today} onToggle={() => {}} onEdit={() => {}} dragging />
          ) : null}
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
      {celebrating && <Confetti />}
      <Toast toast={toast} />
    </main>
  );
}
