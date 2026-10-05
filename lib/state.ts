import { after } from "next/server";
import { prisma } from "./db";
import { computeStreak, dayKey } from "./day";
import { googleConfigured } from "./googleConfig";
import { runMorningReset } from "./topServer";
import { LISTS, type ListKind, type Snapshot } from "./types";

export async function getSnapshot(): Promise<Snapshot> {
  const today = dayKey();
  const resetIds = await runMorningReset(today);
  if (resetIds.length) {
    after(async () => (await import("./google")).syncTasks(resetIds));
  }
  const [tasks, settings, completeDays, todayLog, google] = await Promise.all([
    prisma.task.findMany({ orderBy: [{ position: "asc" }, { createdAt: "asc" }] }),
    prisma.listSetting.findMany(),
    prisma.dayLog.findMany({ where: { top3Complete: true }, select: { date: true } }),
    prisma.dayLog.findUnique({ where: { date: today } }),
    prisma.googleAccount.findUnique({ where: { id: 1 }, select: { email: true } }),
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
    google: { configured: googleConfigured(), connected: !!google, email: google?.email ?? null },
  };
}
