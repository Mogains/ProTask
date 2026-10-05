/** Pure request policy shared by the middleware and the start script. No Node or Next imports. */

const LOOPBACK_HOSTNAMES = new Set(["localhost", "127.0.0.1", "::1", "[::1]"]);

export function isLoopbackHost(hostname: string): boolean {
  const h = hostname.toLowerCase();
  return LOOPBACK_HOSTNAMES.has(h) || /^127(\.\d{1,3}){3}$/.test(h);
}

/** "example.com:3000" -> "example.com", "[::1]:3000" -> "[::1]" */
export function hostnameOf(hostHeader: string): string {
  const h = hostHeader.trim().toLowerCase();
  if (h.startsWith("[")) return h.slice(0, h.indexOf("]") + 1);
  return h.split(":")[0];
}

/**
 * Hosts the app answers to. Loopback names always; anything else must be listed in PUBLIC_HOSTS.
 * Rejecting unknown Host headers blocks DNS-rebinding attacks from web pages you visit.
 */
export function allowedHost(hostHeader: string | null, publicHosts: string[]): boolean {
  if (!hostHeader) return false;
  const name = hostnameOf(hostHeader);
  return isLoopbackHost(name) || publicHosts.map((h) => h.toLowerCase()).includes(name);
}

/** CSRF: state-changing requests must come from a page on this same origin. */
export function sameOrigin(method: string, origin: string | null, host: string | null, proto: string): boolean {
  if (method === "GET" || method === "HEAD" || method === "OPTIONS") return true;
  if (!origin || !host) return false;
  try {
    const o = new URL(origin);
    return o.host.toLowerCase() === host.toLowerCase() && o.protocol === `${proto}:`;
  } catch {
    return false;
  }
}

export function parseList(v: string | undefined): string[] {
  return (v ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

export function buildCsp(nonce: string, dev: boolean): string {
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${dev ? " 'unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'", // dnd-kit and progress bars use inline style attributes
    "img-src 'self' data: blob:",
    "font-src 'self'",
    `connect-src 'self'${dev ? " ws: wss:" : ""}`,
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join("; ");
}
