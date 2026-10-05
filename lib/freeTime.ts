export type CalEvent = { id: string; title: string; start: string; end: string; allDay: boolean };
export type Gap = { start: Date; end: Date; minutes: number };

/** Free gaps between timed events inside [dayStart, dayEnd], starting no earlier than `now`. */
export function freeSlots(events: CalEvent[], dayStart: Date, dayEnd: Date, now: Date, minMinutes = 15): Gap[] {
  const from = Math.max(dayStart.getTime(), now.getTime());
  const to = dayEnd.getTime();
  if (from >= to) return [];
  const busy = events
    .filter((e) => !e.allDay)
    .map((e) => [new Date(e.start).getTime(), new Date(e.end).getTime()] as const)
    .filter(([s, e]) => e > from && s < to)
    .sort((a, b) => a[0] - b[0]);

  const gaps: Gap[] = [];
  let cursor = from;
  for (const [s, e] of busy) {
    if (s > cursor) push(cursor, s);
    cursor = Math.max(cursor, e);
  }
  push(cursor, to);
  return gaps;

  function push(s: number, e: number) {
    const minutes = Math.floor((Math.min(e, to) - s) / 60_000);
    if (minutes >= minMinutes) gaps.push({ start: new Date(s), end: new Date(Math.min(e, to)), minutes });
  }
}
