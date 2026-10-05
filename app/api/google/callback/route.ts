import { after, NextResponse, type NextRequest } from "next/server";
import { backfill, connectWithCode } from "@/lib/google";

export async function GET(req: NextRequest) {
  const p = req.nextUrl.searchParams;
  const back = (status: string) => {
    const res = NextResponse.redirect(new URL(`/?google=${status}`, req.url));
    res.cookies.delete("g_oauth_state");
    return res;
  };
  if (p.get("error")) return back("denied");
  const code = p.get("code");
  if (!code || !p.get("state") || p.get("state") !== req.cookies.get("g_oauth_state")?.value) return back("bad-state");
  try {
    await connectWithCode(code);
  } catch (e) {
    console.error("[calendar] connect failed:", e);
    return back("error");
  }
  after(() => backfill().catch((e) => console.error("[calendar] backfill failed:", e)));
  return back("connected");
}
