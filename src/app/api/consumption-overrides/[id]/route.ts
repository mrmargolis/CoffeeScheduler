import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const db = getDb();
  const { id } = await params;

  const existing = db
    .prepare("SELECT * FROM consumption_overrides WHERE id = ?")
    .get(Number(id));

  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  db.prepare("DELETE FROM consumption_overrides WHERE id = ?").run(Number(id));

  return NextResponse.json({ success: true });
}
