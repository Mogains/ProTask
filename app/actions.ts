"use server";

import { prisma } from "@/lib/db";
import { getSnapshot } from "@/lib/state";
import { sortTasks } from "@/lib/sort";
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
  return result();
}

export async function toggleComplete(id: string, completed: boolean): Promise<ActionResult> {
  await prisma.task.update({
    where: { id },
    data: { completed, completedAt: completed ? new Date() : null },
  });
  return result();
}

/** Persist a list's full order after a drag. Also moves tasks into `list` if they came from the other list. */
export async function reorderList(list: string, orderedIds: string[]): Promise<ActionResult> {
  if (!isListKind(list)) throw new Error("Unknown list.");
  await prisma.$transaction([
    ...orderedIds.map((id, i) => prisma.task.updateMany({ where: { id }, data: { list, position: (i + 1) * 1000 } })),
    // A manual drag switches this list to manual order until auto sort is turned back on.
    prisma.listSetting.upsert({ where: { list }, create: { list, autoSort: false }, update: { autoSort: false } }),
  ]);
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
