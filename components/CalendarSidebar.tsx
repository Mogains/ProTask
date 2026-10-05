"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { freeSlots, type CalEvent } from "@/lib/freeTime";
import { formatMinutes } from "./format";

type Props = {
  configured: boolean;
  connected: boolean;
  email: string | null;
  onDisconnect: () => void;
};

const time = (d: Date) => d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
const WORK_START = 8;
const WORK_END = 20;

export function CalendarSidebar({ configured, connected, email, onDisconnect }: Props) {
  const [events, setEvents] = useState<CalEvent[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(() => new Date());

  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/google/events", { cache: "no-store" });
      const data = await res.json();
      setEvents(data.events ?? []);
      setError(data.error ?? null);
    } catch {
      setError("Couldn't load your calendar.");
    }
    setNow(new Date());
  }, []);

  useEffect(() => {
    if (!connected) return;
    load();
    const id = setInterval(load, 5 * 60_000);
    const onVis = () => document.visibilityState === "visible" && load();
    document.addEventListener("visibilitychange", onVis);
    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [connected, load]);

  const gaps = useMemo(() => {
    if (!events) return [];
    const s = new Date(now);
    s.setHours(WORK_START, 0, 0, 0);
    const e = new Date(now);
    e.setHours(WORK_END, 0, 0, 0);
    return freeSlots(events, s, e, now, 20);
  }, [events, now]);

  return (
    <aside className="rounded-2xl border border-zinc-200 p-4 dark:border-zinc-800" aria-label="Today's calendar">
      <div className="mb-3 flex items-center gap-2">
        <h2 className="font-semibold">Today’s calendar</h2>
        {connected && (
          <button
            type="button"
            onClick={load}
            className="ml-auto text-xs text-zinc-500 hover:text-zinc-300"
            aria-label="Refresh calendar"
          >
            ↻
          </button>
        )}
      </div>

      {!connected ? (
        <div className="space-y-3 text-sm text-zinc-500">
          <p>
            See your meetings and free time next to your tasks. Tasks with due dates and your Top 3 show up on a “Top 3”
            calendar.
          </p>
          <a
            href="/api/google/connect"
            className="inline-flex items-center gap-2 rounded-lg border border-zinc-300 px-3 py-2 font-medium text-zinc-800 hover:border-amber-400 dark:border-zinc-700 dark:text-zinc-100"
          >
            <span aria-hidden>📅</span> Connect Google Calendar
          </a>
          {!configured && (
            <p className="text-xs">
              Needs Google OAuth keys in <code>.env</code>. See the README.
            </p>
          )}
        </div>
      ) : (
        <div className="space-y-4 text-sm">
          {error && <p className="text-rose-500">{error}</p>}
          {events === null ? (
            <p className="text-zinc-500">Loading…</p>
          ) : events.length === 0 ? (
            <p className="text-zinc-500">Nothing on your calendar today. Wide open.</p>
          ) : (
            <ul className="space-y-1.5">
              {events.map((e) => {
                const past = !e.allDay && new Date(e.end) < now;
                return (
                  <li
                    key={e.id}
                    className={`flex gap-3 rounded-lg bg-zinc-500/5 px-2.5 py-1.5 ${past ? "opacity-40" : ""}`}
                  >
                    <span className="w-24 shrink-0 tabular-nums text-zinc-500">
                      {e.allDay ? "All day" : `${time(new Date(e.start))}`}
                    </span>
                    <span className="min-w-0 truncate">{e.title}</span>
                  </li>
                );
              })}
            </ul>
          )}

          {events && (
            <div>
              <h3 className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-emerald-600 dark:text-emerald-400">
                Free time
              </h3>
              {gaps.length ? (
                <ul className="space-y-1">
                  {gaps.map((g) => (
                    <li
                      key={+g.start}
                      className="flex justify-between rounded-lg border border-emerald-500/20 px-2.5 py-1.5"
                    >
                      <span className="tabular-nums">
                        {time(g.start)} – {time(g.end)}
                      </span>
                      <span className="text-zinc-500">{formatMinutes(g.minutes)}</span>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-zinc-500">No free blocks left between 8am and 8pm.</p>
              )}
            </div>
          )}

          <div className="flex items-center gap-2 border-t border-zinc-200 pt-3 text-xs text-zinc-500 dark:border-zinc-800">
            <span className="truncate">Connected{email ? ` as ${email}` : ""}</span>
            <button type="button" onClick={onDisconnect} className="ml-auto shrink-0 hover:text-rose-500">
              Disconnect
            </button>
          </div>
        </div>
      )}
    </aside>
  );
}
