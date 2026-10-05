"use client";

import { useActionState } from "react";
import type { AuthState } from "@/app/auth-actions";

type Props = {
  mode: "setup" | "login";
  action: (state: AuthState, form: FormData) => Promise<AuthState>;
  minLength?: number;
};

const input =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-amber-400 dark:border-zinc-700 dark:bg-zinc-900";

export function AuthForm({ mode, action, minLength }: Props) {
  const [state, formAction, pending] = useActionState(action, undefined);
  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-6 px-4">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">
          Top <span className="text-amber-400">3</span>
        </h1>
        <p className="mt-1 text-sm text-zinc-500">
          {mode === "setup"
            ? "Choose a password. You'll need it to open your tasks from now on."
            : "Enter your password to continue."}
        </p>
      </div>
      <form action={formAction} className="flex flex-col gap-3">
        <input
          className={input}
          type="password"
          name="password"
          placeholder="Password"
          autoComplete={mode === "setup" ? "new-password" : "current-password"}
          minLength={minLength}
          required
          autoFocus
        />
        {mode === "setup" && (
          <input className={input} type="password" name="confirm" placeholder="Confirm password" autoComplete="new-password" required />
        )}
        {state?.error && <p className="text-sm text-red-500">{state.error}</p>}
        <button
          type="submit"
          disabled={pending}
          className="rounded-lg bg-amber-400 px-3 py-2 text-sm font-medium text-zinc-950 hover:bg-amber-300 disabled:opacity-60"
        >
          {mode === "setup" ? "Set password" : "Log in"}
        </button>
      </form>
    </main>
  );
}
