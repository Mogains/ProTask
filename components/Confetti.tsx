"use client";

import { useMemo } from "react";

const COLORS = ["#fbbf24", "#34d399", "#60a5fa", "#f472b6", "#a78bfa", "#fb923c"];

/** Lightweight CSS confetti. Mount it to fire once; unmount to clear. */
export function Confetti() {
  const pieces = useMemo(
    () =>
      Array.from({ length: 90 }, (_, i) => ({
        i,
        left: Math.random() * 100,
        dx: `${(Math.random() - 0.5) * 30}vw`,
        delay: Math.random() * 0.5,
        duration: 1.8 + Math.random() * 1.4,
        color: COLORS[i % COLORS.length],
        w: 6 + Math.random() * 6,
        round: Math.random() > 0.6,
      })),
    [],
  );
  return (
    <div aria-hidden className="pointer-events-none fixed inset-0 z-50 overflow-hidden">
      {pieces.map((p) => (
        <span
          key={p.i}
          style={
            {
              left: `${p.left}%`,
              width: p.w,
              height: p.round ? p.w : p.w * 0.45,
              background: p.color,
              borderRadius: p.round ? "50%" : 2,
              animation: `confetti-fall ${p.duration}s ${p.delay}s cubic-bezier(.2,.6,.4,1) forwards`,
              "--dx": p.dx,
            } as React.CSSProperties
          }
          className="absolute top-0 block"
        />
      ))}
    </div>
  );
}
