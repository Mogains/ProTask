import { NextResponse } from "next/server";
import { todaysEvents } from "@/lib/google";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const events = await todaysEvents();
    return NextResponse.json(events ? { connected: true, events } : { connected: false, events: [] });
  } catch (e) {
    console.error("[calendar] list failed:", e);
    return NextResponse.json({ connected: true, events: [], error: "Couldn't load your calendar." }, { status: 502 });
  }
}
