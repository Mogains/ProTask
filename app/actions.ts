"use server";

import { prisma } from "@/lib/db";
import { getSnapshot } from "@/lib/state";
import { dayKey } from "@/lib/day";
import { sortTasks } from "@/lib/sort";
import { planTopAssignment, TOP3_FULL_MESSAGE } from "@/lib/top3";
import { refreshTodayLog } from "@/lib/topServer";
import { normalizeInput } from "@/lib/taskInput";
import { isListKind, type ActionResult, type ListKind, type Snapshot, type TaskInput } from "@/lib/types";

async function result(error?: string): Promise<ActionResult> {
  return { snapshot: await getSnapshot(), ...(error ? { error } : {}) };
}

async function endOfList(list: ListKind): Promise<number> {
  const last = await prisma.task.findFirst({ where: { list }, orderBy: { position: "desc" } });
  return (last?.position ?? 0) + 1000;
}

export async function getState(): Promise<Snapshot> {
  return getSnapshot();
}

export async function createTask(input: TaskInput): Promise<ActionResult> {
  const data = normalizeInput(input);
  await prisma.task.create({ data: { ...data, position: await endOfList(data.list) } });
  return result();
}

export async function updateTask(id: string, input: TaskInput): Promise<ActionResult> {
  const data = normalizeInput(input);
  const existing = await prisma.task.findUniqueOrThrow({ where: { id } });
  const position = existing.list === data.list ? existing.position : await endOfList(data.list);
  await prisma.task.update({ where: { id }, data: { ...data, position } });
  return result();
}

export async function deleteTask(id: string): Promise<ActionResult> {
  await prisma.task.deleteMany({ where: { id } });
  await refreshTodayLog();
  return result();
}

export async function toggleComplete(id: string, completed: boolean): Promise<ActionResult> {
  await prisma.task.update({
    where: { id },
    data: { completed, completedAt: completed ? new Date() : null },
  });
  await refreshTodayLog();
  return result();
}

/** Persist a list's full order after a drag. Also moves tasks into `list` if they came from the other list. */
export async function reorderList(list: string, orderedIds: string[]): Promise<ActionResult> {
  if (!isListKind(list)) throw new Error("Unknown list.");
  await prisma.$transaction([
    ...orderedIds.map((id, i) => prisma.task.updateMany({ where: { id }, data: { list, position: (i + 1) * 1000, topSlot: null, topDate: null } }),
    ),
    // A manual drag switches this list to manual order until auto sort is turned back on.
    prisma.listSetting.upsert({ where: { list }, create: { list, autoSort: false }, update: { autoSort: false } }),
  ]);
  await refreshTodayLog();
  return result();
}

/** Turn auto sort on or off. Either way the current sorted order is saved, so nothing jumps. */
export async function setAutoSort(list: string, autoSort: boolean): Promise<ActionResult> {
  if (!isListKind(list)) throw new Error("Unknown list.");
  const tasks = sortTasks(await prisma.task.findMany({ where: { list, completed: false, topSlot: null } }));
  await prisma.$transaction([
    ...tasks.map((t, i) => prisma.task.update({ where: { id: t.id }, data: { position: (i + 1) * 1000 } })),
    prisma.listSetting.upsert({ where: { list }, create: { list, autoSort }, update: { autoSort } }),
  ]);
  return result();
}

/** Pin a task to the Top 3. Without a slot it takes the first free one; a 4th is refused. */
export async function assignTop(taskId: string, slot?: number): Promise<ActionResult> {
  const today = dayKey();
  const task = await prisma.task.findUniqueOrThrow({ where: { id: taskId } });
  if (task.completed) return result("That one's already done ✓");
  const pinned = await prisma.task.findMany({ where: { topSlot: { not: null } }, select: { id: true, topSlot: true } });
  const plan = planTopAssignment(pinned.map((t) => ({ slot: t.topSlot!, taskId: t.id })), taskId, slot);
  if (!plan.ok) return result(plan.reason === "full" ? TOP3_FULL_MESSAGE : "Pick slot 1, 2 or 3.");

  await prisma.$transaction(async (tx) => {
    // Clear both slots first so the unique constraint on topSlot is never violated mid-swap.
    const clear = [taskId, plan.displaced?.taskId].filter((x): x is string => !!x);
    await tx.task.updateMany({ where: { id: { in: clear } }, data: { topSlot: null } });
    await tx.task.update({ where: { id: taskId }, data: { topSlot: plan.slot, topDate: today } });
    if (plan.displaced) {
      const toSlot = plan.displaced.toSlot;
      await tx.task.update({
        where: { id: plan.displaced.taskId },
        data: { topSlot: toSlot, topDate: toSlot ? today : null },
      });
    }
  });
  await refreshTodayLog(today);
  return result();
}

/** Unpin a task. It reappears in its original list. */
export async function removeTop(taskId: string): Promise<ActionResult> {
  await prisma.task.updateMany({ where: { id: taskId }, data: { topSlot: null, topDate: null } });
  await refreshTodayLog();
  return result();
}

/** Hide today's "pick your Top 3" prompt. */
export async function dismissPrompt(): Promise<ActionResult> {
  const date = dayKey();
  await prisma.dayLog.upsert({ where: { date }, create: { date, promptDismissed: true }, update: { promptDismissed: true } });
  return result();
}
