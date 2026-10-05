import { prisma } from "./db";
import { dayKey } from "./day";

/**
 * Morning reset: anything pinned on an earlier day leaves the Top 3.
 * Unfinished tasks reappear in their original list at their original position
 * (they never left it, only their slot is cleared). Finished ones move to Done.
 * Returns the ids that changed so calendar events can be updated.
 */
export async function runMorningReset(today = dayKey()): Promise<string[]> {
  const stale = await prisma.task.findMany({
    where: { topSlot: { not: null }, OR: [{ topDate: null }, { topDate: { not: today } }] },
    select: { id: true },
  });
  if (!stale.length) return [];
  const ids = stale.map((t) => t.id);
  await prisma.task.updateMany({ where: { id: { in: ids } }, data: { topSlot: null, topDate: null } });
  return ids;
}

/** Record whether all three of today's Top 3 are done. Drives the streak. */
export async function refreshTodayLog(today = dayKey()) {
  const tops = await prisma.task.findMany({ where: { topSlot: { not: null }, topDate: today } });
  const top3Complete = tops.length === 3 && tops.every((t) => t.completed);
  await prisma.dayLog.upsert({ where: { date: today }, create: { date: today, top3Complete }, update: { top3Complete } });
}
