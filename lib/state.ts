import { prisma } from "./db";
import { computeStreak, dayKey } from "./day";
import { runMorningReset } from "./topServer";
import { LISTS, type ListKind, type Snapshot } from "./types";

export async function getSnapshot(): Promise<Snapshot> {
  const today = dayKey();
  await runMorningReset(today);
  const [tasks, settings, completeDays, todayLog] = await Promise.all([
    prisma.task.findMany({ orderBy: [{ position: "asc" }, { createdAt: "asc" }] }),
    prisma.listSetting.findMany(),
    prisma.dayLog.findMany({ where: { top3Complete: true }, select: { date: true } }),
    prisma.dayLog.findUnique({ where: { date: today } }),
  ]);
  const autoSort = Object.fromEntries(
    LISTS.map((l) => [l, settings.find((s) => s.list === l)?.autoSort ?? true]),
  ) as Record<ListKind, boolean>;
  return {
    tasks,
    today,
    streak: computeStreak(new Set(completeDays.map((d) => d.date)), today),
    autoSort,
    promptDismissed: todayLog?.promptDismissed ?? false,
    google: { configured: false, connected: false, email: null },
  };
}
