import { NextResponse, type NextRequest } from "next/server";
import { isSetUp, sessionCookieName, validSession } from "@/lib/auth";
import { allowedHost, buildCsp, hostnameOf, isLoopbackHost, parseList, sameOrigin } from "@/lib/netPolicy";

// Node runtime so the session can be checked against the database.
export const config = {
  runtime: "nodejs",
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};

const PUBLIC_PATHS = new Set(["/login", "/setup"]);

function plain(status: number, text: string) {
  return new NextResponse(text, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
}

export async function middleware(req: NextRequest) {
  const host = req.headers.get("host");
  const publicHosts = parseList(process.env.PUBLIC_HOSTS);
  // Only trust X-Forwarded-Proto behind your own TLS proxy.
  const proto =
    process.env.TRUST_PROXY === "1"
      ? (req.headers.get("x-forwarded-proto")?.split(",")[0].trim() ?? "http")
      : req.nextUrl.protocol.replace(":", "");
  const secure = proto === "https";
  const local = !!host && isLoopbackHost(hostnameOf(host));

  // 1. Unknown Host header: likely DNS rebinding from a web page.
  if (!allowedHost(host, publicHosts)) return plain(421, "Unknown host.");
  // 2. Off localhost, only over HTTPS.
  if (!local && !secure) return plain(403, "HTTPS is required when ProTask is not on localhost.");
  // 3. CSRF: state-changing requests must come from this origin.
  if (!sameOrigin(req.method, req.headers.get("origin"), host, proto)) return plain(403, "Cross-site request refused.");

  // 4. Login.
  const path = req.nextUrl.pathname;
  const setUp = await isSetUp();
  if (!setUp) {
    // First run: setting the password is only possible from this machine.
    if (path !== "/setup") return redirect(req, "/setup");
    if (!local) return plain(403, "Set the password from the computer ProTask runs on.");
  } else if (!PUBLIC_PATHS.has(path) || path === "/setup") {
    if (path === "/setup") return redirect(req, "/login");
    const ok = await validSession(req.cookies.get(sessionCookieName(secure))?.value);
    if (!ok) {
      if (path.startsWith("/api/") || req.method !== "GET") return plain(401, "Log in first.");
      return redirect(req, "/login");
    }
  }

  // 5. Security headers, with a per-request CSP nonce that Next applies to its own scripts.
  const nonce = Buffer.from(crypto.getRandomValues(new Uint8Array(16))).toString("base64");
  const csp = buildCsp(nonce, process.env.NODE_ENV !== "production");
  const reqHeaders = new Headers(req.headers);
  reqHeaders.set("x-nonce", nonce);
  reqHeaders.set("x-protask-secure", secure ? "1" : "0");
  reqHeaders.set("content-security-policy", csp);
  const res = NextResponse.next({ request: { headers: reqHeaders } });
  return withSecurityHeaders(res, csp, secure);
}

function redirect(req: NextRequest, to: string) {
  return withSecurityHeaders(NextResponse.redirect(new URL(to, req.url)), null, false);
}

function withSecurityHeaders(res: NextResponse, csp: string | null, secure: boolean) {
  if (csp) res.headers.set("Content-Security-Policy", csp);
  res.headers.set("X-Frame-Options", "DENY");
  res.headers.set("X-Content-Type-Options", "nosniff");
  res.headers.set("Referrer-Policy", "no-referrer");
  res.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()");
  res.headers.set("Cross-Origin-Opener-Policy", "same-origin");
  res.headers.set("Cross-Origin-Resource-Policy", "same-origin");
  res.headers.set("Cache-Control", "no-store");
  if (secure) res.headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  return res;
}
