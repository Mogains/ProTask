/**
 * Safe logging. Google client errors carry the request config (Authorization header, event body
 * with task titles) and sometimes URLs with tokens, so never log an error object as is.
 */

const PATTERNS: [RegExp, string][] = [
  [/ya29\.[\w-]+/g, "[access-token]"],
  [/1\/\/[\w-]{20,}/g, "[refresh-token]"],
  [/GOCSPX-[\w-]+/g, "[client-secret]"],
  [/Bearer\s+[\w.~+/-]+=*/gi, "Bearer [redacted]"],
  [/eyJ[\w-]+\.[\w-]+\.[\w-]+/g, "[jwt]"],
  [/https?:\/\/\S+/gi, "[url]"],
  [/webcal:\/\/\S+/gi, "[url]"],
  [/[\w.+-]+@[\w-]+\.[\w.-]+/g, "[email]"],
];

export function scrub(text: string): string {
  return PATTERNS.reduce((s, [re, rep]) => s.replace(re, rep), text).slice(0, 300);
}

/** A short, content-free description of an error: HTTP status, error code and a scrubbed message. */
export function describeError(e: unknown): string {
  const err = e as {
    name?: string;
    code?: string | number;
    status?: number;
    message?: string;
    response?: { status?: number; data?: { error?: string | { status?: string } } };
  };
  const status = err?.response?.status ?? err?.status;
  const data = err?.response?.data?.error;
  const reason = typeof data === "string" ? data : data?.status;
  const parts = [
    err?.name && err.name !== "Error" ? err.name : null,
    status ? `HTTP ${status}` : null,
    reason ?? (typeof err?.code === "string" ? err.code : null),
  ].filter(Boolean);
  // Messages from Google are generic ("Not Found", "invalid_grant"); scrub anyway in case one echoes input.
  const msg = e instanceof Error ? scrub(e.message) : null;
  return [...parts, msg].filter(Boolean).join(" · ") || "unknown error";
}

/** console.error replacement for anything that may hold tokens, URLs or task contents. */
export function logError(where: string, e: unknown) {
  console.error(`[${where}] ${describeError(e)}`);
}
