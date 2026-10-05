import { beforeEach, describe, expect, it } from "vitest";
import {
  createSession,
  hashPassword,
  lockoutMs,
  login,
  passwordProblem,
  setOwnerPassword,
  validSession,
  verifyPassword,
} from "@/lib/auth";
import { prisma } from "@/lib/db";
import { allowedHost, isLoopbackHost, sameOrigin } from "@/lib/netPolicy";

const PW = "correct horse battery";

describe("password hashing", () => {
  it("stores argon2id and verifies only the right password", async () => {
    const h = await hashPassword(PW);
    expect(h).toMatch(/^\$argon2id\$v=19\$m=65536,t=3,p=1\$/);
    expect(h).not.toContain(PW);
    expect(await verifyPassword(PW, h)).toBe(true);
    expect(await verifyPassword("wrong password!", h)).toBe(false);
    expect(await hashPassword(PW)).not.toBe(h); // salted
  });

  it("enforces a minimum length and matching confirmation", () => {
    expect(passwordProblem("short")).toMatch(/12/);
    expect(passwordProblem(PW, "different")).toMatch(/match/);
    expect(passwordProblem(PW, PW)).toBeNull();
  });
});

describe("login", () => {
  beforeEach(async () => {
    await prisma.session.deleteMany();
    await prisma.authConfig.deleteMany();
    await setOwnerPassword(PW);
  });

  it("can only set the owner password once", async () => {
    await expect(setOwnerPassword("another long password")).rejects.toThrow();
  });

  it("backs off exponentially after five failures and blocks even the right password while locked", async () => {
    expect([4, 5, 6, 7].map(lockoutMs)).toEqual([0, 30_000, 60_000, 120_000]);
    expect(lockoutMs(50)).toBe(60 * 60_000);

    const t0 = new Date(2026, 0, 1, 12);
    for (let i = 0; i < 4; i++) expect(await login("nope", t0)).toMatchObject({ ok: false, error: "Wrong password." });
    expect(await login("nope", t0)).toMatchObject({ ok: false, retryAfterMs: 30_000 });
    expect(await login(PW, new Date(t0.getTime() + 10_000))).toMatchObject({ ok: false, error: "Too many attempts." });
    const after = await login(PW, new Date(t0.getTime() + 31_000));
    expect(after.ok).toBe(true);
    expect((await prisma.authConfig.findUniqueOrThrow({ where: { id: 1 } })).failedCount).toBe(0);
  });

  it("issues sessions that are stored hashed and expire", async () => {
    const r = await login(PW);
    if (!r.ok) throw new Error("login failed");
    expect(await validSession(r.token)).toBe(true);
    expect(await prisma.session.findFirst({ where: { id: r.token } })).toBeNull(); // only the hash is stored
    expect(await validSession("forged")).toBe(false);
    const old = await createSession(new Date(2020, 0, 1));
    expect(await validSession(old)).toBe(false);
  });
});

describe("request policy", () => {
  it("accepts loopback hosts and listed public hosts only (DNS rebinding)", () => {
    expect(allowedHost("localhost:3000", [])).toBe(true);
    expect(allowedHost("127.0.0.1:3000", [])).toBe(true);
    expect(allowedHost("[::1]:3000", [])).toBe(true);
    expect(allowedHost("evil.example:3000", [])).toBe(false);
    expect(allowedHost("tasks.example.com", ["tasks.example.com"])).toBe(true);
    expect(allowedHost(null, [])).toBe(false);
    expect(isLoopbackHost("192.168.1.5")).toBe(false);
  });

  it("refuses cross-site state changes", () => {
    expect(sameOrigin("GET", null, "localhost:3000", "http")).toBe(true);
    expect(sameOrigin("POST", "http://localhost:3000", "localhost:3000", "http")).toBe(true);
    expect(sameOrigin("POST", "https://evil.example", "localhost:3000", "http")).toBe(false);
    expect(sameOrigin("POST", null, "localhost:3000", "http")).toBe(false);
    expect(sameOrigin("POST", "http://tasks.example.com", "tasks.example.com", "https")).toBe(false);
  });
});
