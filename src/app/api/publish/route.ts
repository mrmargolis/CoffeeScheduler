import { NextResponse } from "next/server";
import { runPublish } from "@/lib/run-publish";

export async function POST() {
  const result = await runPublish();
  if (!result.ok) {
    return NextResponse.json(
      { error: "Publish failed", details: result.error },
      { status: 500 }
    );
  }
  return NextResponse.json({ ok: true });
}
