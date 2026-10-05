import { prisma } from "./db";

/**
 * Migration: before multiple links, a task stored one event id in Task.calendarEventId.
 * That event was the due-date event if the task had a due date, otherwise today's Top 3 event.
 * Runs before every sync; a no-op once the column is empty.
 */
export async function migrateLegacyLinks() {
  const legacy = await prisma.task.findMany({
    where: { calendarEventId: { not: null } },
    select: { id: true, dueAt: true, calendarEventId: true },
  });
  for (const t of legacy) {
    const kind = t.dueAt ? "DUE" : "PINNED";
    await prisma.$transaction([
      prisma.eventLink.upsert({
        where: { eventId: t.calendarEventId! },
        create: { taskId: t.id, kind, eventId: t.calendarEventId! },
        update: {},
      }),
      prisma.task.update({ where: { id: t.id }, data: { calendarEventId: null } }),
    ]);
  }
}
