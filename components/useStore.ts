"use client";

import { useCallback, useRef, useState } from "react";
import { getState } from "@/app/actions";
import type { ActionResult, Snapshot } from "@/lib/types";

/**
 * Holds the app state and runs mutations optimistically:
 * apply the local change at once, then replace it with the server's snapshot.
 * Only the most recent mutation's response is applied, so rapid clicks never flicker.
 */
export function useStore(initial: Snapshot) {
  const [snap, setSnap] = useState(initial);
  const [toast, setToast] = useState<{ id: number; text: string } | null>(null);
  const seq = useRef(0);

  const showToast = useCallback((text: string) => {
    const id = Date.now();
    setToast({ id, text });
    setTimeout(() => setToast((t) => (t?.id === id ? null : t)), 3200);
  }, []);

  const run = useCallback(
    async (optimistic: ((s: Snapshot) => Snapshot) | null, call: () => Promise<ActionResult>) => {
      const mine = ++seq.current;
      if (optimistic) setSnap(optimistic);
      try {
        const res = await call();
        if (res.error) showToast(res.error);
        if (mine === seq.current) setSnap(res.snapshot);
        return res;
      } catch (e) {
        showToast(e instanceof Error && e.message ? e.message : "Couldn't save. Re-syncing…");
        const fresh = await getState().catch(() => null);
        if (fresh && mine === seq.current) setSnap(fresh);
        return null;
      }
    },
    [showToast],
  );

  return { snap, setSnap, run, toast, showToast };
}
