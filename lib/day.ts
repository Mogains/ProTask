/** Hour (local) at which a new day starts. Before this hour it still counts as "yesterday". */
export const RESET_HOUR = (() => {
  const n = Number(process.env.NEXT_PUBLIC_RESET_HOUR ?? 4);
  return Number.isInteger(n) && n >= 0 && n <= 23 ? n : 4;
})();

const pad = (n: number) => String(n).padStart(2, "0");

/** Local calendar date as YYYY-MM-DD. */
export function localDateKey(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** The app's notion of "today", which rolls over at RESET_HOUR rather than midnight. */
export function dayKey(now: Date = new Date(), resetHour: number = RESET_HOUR): string {
  return localDateKey(new Date(now.getTime() - resetHour * 3_600_000));
}

export function parseKey(key: string): Date {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function addDays(key: string, days: number): string {
  const d = parseKey(key);
  d.setDate(d.getDate() + days);
  return localDateKey(d);
}

/**
 * Consecutive days (ending today, or yesterday if today isn't finished yet)
 * on which all of the Top 3 were completed.
 */
export function computeStreak(completeDays: Set<string>, today: string): number {
  let key = completeDays.has(today) ? today : addDays(today, -1);
  let n = 0;
  while (completeDays.has(key)) {
    n++;
    key = addDays(key, -1);
  }
  return n;
}

export function hhmm(d: Date): string {
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
