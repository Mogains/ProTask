import { execFile, spawn } from "node:child_process";
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { promisify } from "node:util";
import { prisma } from "./db";

/**
 * Where the Google OAuth tokens live. Never in plain text in the database or a file:
 * - "keychain" (default on macOS): one generic-password item in the login Keychain.
 * - "encrypted" (default elsewhere): AES-256-GCM ciphertext in the database, keyed by TOKEN_ENCRYPTION_KEY.
 * - "memory": tests only.
 */
export type GoogleTokens = { refreshToken: string; accessToken?: string | null; expiresAt?: number | null };

type Backend = {
  get(): Promise<GoogleTokens | null>;
  set(t: GoogleTokens): Promise<void>;
  clear(): Promise<void>;
};

const SERVICE = "ProTask Web: Google Calendar";
const ACCOUNT = "oauth-tokens";
const run = promisify(execFile);

/** Writes go through `security -i` on stdin, so the token never appears in a process argument list. */
function securityStdin(command: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const p = spawn("/usr/bin/security", ["-i"], { stdio: ["pipe", "ignore", "pipe"] });
    let err = "";
    p.stderr.on("data", (d) => (err += d));
    p.on("error", reject);
    p.on("close", (code) => (code === 0 && !err.trim() ? resolve() : reject(new Error("Keychain write failed"))));
    p.stdin.end(command + "\n");
  });
}

const keychain: Backend = {
  async get() {
    try {
      const { stdout } = await run("/usr/bin/security", ["find-generic-password", "-s", SERVICE, "-a", ACCOUNT, "-w"]);
      return parse(stdout.trim());
    } catch {
      return null; // not found
    }
  },
  async set(t) {
    const hex = Buffer.from(JSON.stringify(t)).toString("hex");
    await securityStdin(`add-generic-password -U -s "${SERVICE}" -a ${ACCOUNT} -X ${hex}`);
  },
  async clear() {
    await run("/usr/bin/security", ["delete-generic-password", "-s", SERVICE, "-a", ACCOUNT]).catch(() => {});
  },
};

function key(): Buffer {
  const raw = process.env.TOKEN_ENCRYPTION_KEY ?? "";
  const buf = Buffer.from(raw, "base64");
  if (buf.length !== 32) {
    throw new Error("TOKEN_ENCRYPTION_KEY must be 32 random bytes, base64. Generate one with: openssl rand -base64 32");
  }
  return buf;
}

export function encrypt(plain: string, k = key()): string {
  const iv = randomBytes(12);
  const c = createCipheriv("aes-256-gcm", k, iv);
  const body = Buffer.concat([c.update(plain, "utf8"), c.final()]);
  return ["v1", iv.toString("base64"), c.getAuthTag().toString("base64"), body.toString("base64")].join(".");
}

export function decrypt(blob: string, k = key()): string {
  const [v, iv, tag, body] = blob.split(".");
  if (v !== "v1") throw new Error("Unknown token format");
  const d = createDecipheriv("aes-256-gcm", k, Buffer.from(iv, "base64"));
  d.setAuthTag(Buffer.from(tag, "base64"));
  return Buffer.concat([d.update(Buffer.from(body, "base64")), d.final()]).toString("utf8");
}

const encrypted: Backend = {
  async get() {
    const a = await prisma.googleAccount.findUnique({ where: { id: 1 }, select: { tokenCipher: true } });
    return a?.tokenCipher ? parse(decrypt(a.tokenCipher)) : null;
  },
  async set(t) {
    const tokenCipher = encrypt(JSON.stringify(t));
    await prisma.googleAccount.upsert({ where: { id: 1 }, create: { id: 1, tokenCipher }, update: { tokenCipher } });
  },
  async clear() {
    await prisma.googleAccount.updateMany({ where: { id: 1 }, data: { tokenCipher: null } });
  },
};

let memoryValue: GoogleTokens | null = null;
const memory: Backend = {
  async get() {
    return memoryValue;
  },
  async set(t) {
    memoryValue = { ...t };
  },
  async clear() {
    memoryValue = null;
  },
};

function parse(s: string): GoogleTokens | null {
  try {
    const t = JSON.parse(s) as GoogleTokens;
    return typeof t?.refreshToken === "string" && t.refreshToken ? t : null;
  } catch {
    return null;
  }
}

export function tokenBackendName(): "keychain" | "encrypted" | "memory" {
  const v = process.env.TOKEN_STORE;
  if (v === "keychain" || v === "encrypted" || v === "memory") return v;
  return process.platform === "darwin" ? "keychain" : "encrypted";
}

function backend(): Backend {
  return { keychain, encrypted, memory }[tokenBackendName()];
}

/**
 * One-time migration: older versions kept the tokens in plain text columns.
 * Move them into the secure store, blank the columns and VACUUM so the old bytes leave the file.
 */
async function migrateLegacy() {
  const a = await prisma.googleAccount.findUnique({ where: { id: 1 } });
  if (!a?.refreshToken) return;
  await backend().set({ refreshToken: a.refreshToken, accessToken: a.accessToken, expiresAt: a.expiresAt?.getTime() ?? null });
  await prisma.googleAccount.update({ where: { id: 1 }, data: { refreshToken: null, accessToken: null, expiresAt: null } });
  await prisma.$executeRawUnsafe("VACUUM").catch(() => {});
}

export async function getTokens(): Promise<GoogleTokens | null> {
  await migrateLegacy(); // one cheap row read once the columns are empty
  return backend().get();
}

export async function saveTokens(t: GoogleTokens): Promise<void> {
  await backend().set(t);
}

/** Merge a refresh from the OAuth client (it may send only a new access token). */
export async function updateTokens(patch: Partial<GoogleTokens>): Promise<void> {
  const cur = await backend().get();
  if (!cur && !patch.refreshToken) return;
  await backend().set({ ...(cur ?? { refreshToken: patch.refreshToken! }), ...patch } as GoogleTokens);
}

export async function clearTokens(): Promise<void> {
  await backend().clear();
}
