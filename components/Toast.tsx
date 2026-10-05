"use client";

export function Toast({ toast }: { toast: { id: number; text: string } | null }) {
  if (!toast) return null;
  return (
    <div
      key={toast.id}
      role="status"
      className="animate-toast-in fixed bottom-6 left-1/2 z-50 max-w-[90vw] -translate-x-1/2 rounded-xl bg-zinc-900 px-4 py-2.5 text-sm text-white shadow-xl dark:bg-zinc-100 dark:text-zinc-900"
    >
      {toast.text}
    </div>
  );
}
