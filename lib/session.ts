import { cookies, headers } from "next/headers";
import { sessionCookieName, validSession } from "./auth";

/** Set by the middleware on every request (it overwrites anything the client sends). */
export async function isSecureRequest(): Promise<boolean> {
  return (await headers()).get("x-protask-secure") === "1";
}

export async function currentSessionToken(): Promise<string | undefined> {
  return (await cookies()).get(sessionCookieName(await isSecureRequest()))?.value;
}

/** Defense in depth: every server action checks the session itself, not only the middleware. */
export async function requireSession(): Promise<void> {
  if (!(await validSession(await currentSessionToken()))) throw new Error("Log in first.");
}
