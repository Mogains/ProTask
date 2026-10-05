import { argon2, createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
import { prisma } from "./db";

/**
 * Owner login: one password, set on first run, stored as an argon2id hash.
 * Failed logins back off exponentially; sessions are random 256-bit tokens of which only a hash is stored.
 */

const argon2Async = promisify(argon2);
// OWASP-recommended argon2id parameters (64 MiB, 3 passes).
const PARAMS = { memory: 65536, passes: 3, parallelism: 1, tagLength: 32 };

export const MIN_PASSWORD_LENGTH = 12;
export const SESSION_DAYS = 14;
export const FREE_ATTEMPTS = 5;
const BASE_LOCK_MS = 30_000;
const MAX_LOCK_MS = 60 * 60_000;

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const tag = await argon2Async("argon2id", { message: password, nonce: salt, ...PARAMS });
  const p = PARAMS;
  return `$argon2id$v=19$m=${p.memory},t=${p.passes},p=${p.parallelism}$${salt.toString("base64url")}$${tag.toString("base64url")}`;
}

export async function verifyPassword(password: string, phc: string): Promise<boolean> {
  const m = /^\$argon2id\$v=19\$m=(\d+),t=(\d+),p=(\d+)\$([\w-]+)\$([\w-]+)$/.exec(phc);
  if (!m) return false;
  const expected = Buffer.from(m[5], "base64url");
  const tag = await argon2Async("argon2id", {
    message: password,
    nonce: Buffer.from(m[4], "base64url"),
    memory: +m[1],
    passes: +m[2],
    parallelism: +m[3],
    tagLength: expected.length,
  });
  return timingSafeEqual(tag, expected);
}

/** Lockout after FREE_ATTEMPTS failures: 30 s, doubling each further failure, capped at 1 hour. */
export function lockoutMs(failedCount: number): number {
  if (failedCount < FREE_ATTEMPTS) return 0;
  return Math.min(BASE_LOCK_MS * 2 ** (failedCount - FREE_ATTEMPTS), MAX_LOCK_MS);
}

export async function isSetUp(): Promise<boolean> {
  return (await prisma.authConfig.count()) > 0;
}

export function passwordProblem(password: string, confirm?: string): string | null {
  if (password.length < MIN_PASSWORD_LENGTH) return `Use at least ${MIN_PASSWORD_LENGTH} characters.`;
  if (password.length > 512) return "That password is too long.";
  if (confirm !== undefined && password !== confirm) return "The passwords don't match.";
  return null;
}

/** First run only: refuses if a password already exists. */
export async function setOwnerPassword(password: string): Promise<void> {
  const passwordHash = await hashPassword(password);
  await prisma.authConfig.create({ data: { id: 1, passwordHash } }); // throws if one exists (unique id)
}

export type LoginResult = { ok: true; token: string } | { ok: false; error: string; retryAfterMs?: number };

export async function login(password: string, now = new Date()): Promise<LoginResult> {
  const cfg = await prisma.authConfig.findUnique({ where: { id: 1 } });
  if (!cfg) return { ok: false, error: "Set a password first." };
  if (cfg.lockedUntil && cfg.lockedUntil > now) {
    return { ok: false, error: "Too many attempts.", retryAfterMs: cfg.lockedUntil.getTime() - now.getTime() };
  }
  if (!(await verifyPassword(password, cfg.passwordHash))) {
    const failedCount = cfg.failedCount + 1;
    const lock = lockoutMs(failedCount);
    await prisma.authConfig.update({
      where: { id: 1 },
      data: { failedCount, lockedUntil: lock ? new Date(now.getTime() + lock) : null },
    });
    return lock
      ? { ok: false, error: "Too many attempts.", retryAfterMs: lock }
      : { ok: false, error: "Wrong password." };
  }
  await prisma.authConfig.update({ where: { id: 1 }, data: { failedCount: 0, lockedUntil: null } });
  return { ok: true, token: await createSession(now) };
}

const hashToken = (token: string) => createHash("sha256").update(token).digest("hex");

export async function createSession(now = new Date()): Promise<string> {
  const token = randomBytes(32).toString("base64url");
  await prisma.session.deleteMany({ where: { expiresAt: { lt: now } } });
  await prisma.session.create({
    data: { id: hashToken(token), expiresAt: new Date(now.getTime() + SESSION_DAYS * 86_400_000) },
  });
  return token;
}

export async function validSession(token: string | undefined, now = new Date()): Promise<boolean> {
  if (!token || token.length > 100) return false;
  const s = await prisma.session.findUnique({ where: { id: hashToken(token) } });
  if (!s || s.expiresAt < now) return false;
  if (now.getTime() - s.lastSeenAt.getTime() > 60_000) {
    await prisma.session.update({ where: { id: s.id }, data: { lastSeenAt: now } }).catch(() => {});
  }
  return true;
}

export async function endSession(token: string | undefined) {
  if (token) await prisma.session.deleteMany({ where: { id: hashToken(token) } });
}

/** Cookie name. The __Host- prefix (Secure, no Domain, Path=/) is only allowed over HTTPS. */
export const sessionCookieName = (secure: boolean) => (secure ? "__Host-protask_session" : "protask_session");
