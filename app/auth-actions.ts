"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { endSession, isSetUp, login, passwordProblem, sessionCookieName, SESSION_DAYS, createSession, setOwnerPassword } from "@/lib/auth";
import { currentSessionToken, isSecureRequest } from "@/lib/session";

export type AuthState = { error?: string } | undefined;

async function setSessionCookie(token: string) {
  const secure = await isSecureRequest();
  (await cookies()).set(sessionCookieName(secure), token, {
    httpOnly: true,
    secure,
    sameSite: "lax", // lax so the Google OAuth redirect back to the app keeps you logged in
    path: "/",
    maxAge: SESSION_DAYS * 86_400,
  });
}

export async function setupAction(_: AuthState, form: FormData): Promise<AuthState> {
  if (await isSetUp()) redirect("/login");
  const password = String(form.get("password") ?? "");
  const problem = passwordProblem(password, String(form.get("confirm") ?? ""));
  if (problem) return { error: problem };
  try {
    await setOwnerPassword(password);
  } catch {
    redirect("/login"); // someone set it a moment ago
  }
  await setSessionCookie(await createSession());
  redirect("/");
}

export async function loginAction(_: AuthState, form: FormData): Promise<AuthState> {
  const r = await login(String(form.get("password") ?? ""));
  if (!r.ok) {
    if (r.retryAfterMs) {
      const s = Math.ceil(r.retryAfterMs / 1000);
      return { error: `Too many attempts. Try again in ${s < 90 ? `${s} seconds` : `${Math.ceil(s / 60)} minutes`}.` };
    }
    return { error: r.error };
  }
  await setSessionCookie(r.token);
  redirect("/");
}

export async function logoutAction() {
  await endSession(await currentSessionToken());
  const jar = await cookies();
  jar.delete(sessionCookieName(true));
  jar.delete(sessionCookieName(false));
  redirect("/login");
}
