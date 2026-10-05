import { randomBytes } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "@/lib/db";
import { describeError, scrub } from "@/lib/redact";
import { clearTokens, decrypt, encrypt, getTokens } from "@/lib/tokenStore";

describe("token storage", () => {
  beforeEach(async () => {
    await clearTokens();
    await prisma.googleAccount.deleteMany();
  });

  it("moves legacy plain-text tokens out of the database", async () => {
    await prisma.googleAccount.create({
      data: { id: 1, refreshToken: "1//legacy-refresh", accessToken: "ya29.legacy", expiresAt: new Date(5000) },
    });
    const t = await getTokens();
    expect(t).toEqual({ refreshToken: "1//legacy-refresh", accessToken: "ya29.legacy", expiresAt: 5000 });
    const row = await prisma.googleAccount.findUniqueOrThrow({ where: { id: 1 } });
    expect(row.refreshToken).toBeNull();
    expect(row.accessToken).toBeNull();
    expect(row.expiresAt).toBeNull();
  });

  it("encrypts with AES-GCM and rejects tampering or the wrong key", () => {
    const k = randomBytes(32);
    const blob = encrypt('{"refreshToken":"secret"}', k);
    expect(blob).not.toContain("secret");
    expect(decrypt(blob, k)).toBe('{"refreshToken":"secret"}');
    expect(() => decrypt(blob, randomBytes(32))).toThrow();
    const parts = blob.split(".");
    parts[3] = Buffer.from("tampered").toString("base64");
    expect(() => decrypt(parts.join("."), k)).toThrow();
  });
});

describe("log redaction", () => {
  it("removes tokens, secrets, URLs and emails", () => {
    const s = scrub(
      "Bearer ya29.a0AfH6SMB refresh=1//0gABCDEFGHIJKLMNOPQRSTUVWX GOCSPX-abc123 https://www.googleapis.com/calendar/v3?x=1 me@example.com",
    );
    for (const bad of ["ya29", "1//0g", "GOCSPX", "googleapis", "example.com"]) expect(s).not.toContain(bad);
  });

  it("describes a Google error without its request config or body", () => {
    const err = Object.assign(new Error("Not Found"), {
      response: { status: 404, data: { error: "notFound" } },
      config: { headers: { Authorization: "Bearer ya29.secret" }, data: { summary: "Private task title" } },
    });
    const d = describeError(err);
    expect(d).toContain("HTTP 404");
    expect(d).not.toContain("ya29");
    expect(d).not.toContain("Private task title");
  });
});
