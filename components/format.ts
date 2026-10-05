import { addDays, localDateKey } from "@/lib/day";
import type { Task } from "@/lib/types";

export function formatDue(task: Pick<Task, "dueAt" | "hasDueTime">, today: string) {
  if (!task.dueAt) return null;
  const d = new Date(task.dueAt);
  const key = localDateKey(d);
  let day: string;
  if (key === today) day = "Today";
  else if (key === addDays(today, 1)) day = "Tomorrow";
  else if (key === addDays(today, -1)) day = "Yesterday";
  else day = d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
  const time = task.hasDueTime ? d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }) : "";
  return { label: time ? `${day} ${time}` : day, overdue: key < today };
}

export function formatMinutes(m: number | null) {
  if (!m) return null;
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return m % 60 ? `${h}h ${m % 60}m` : `${h}h`;
}
