import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import { today as getToday } from "@/lib/date-utils";

export async function POST(
  _request: NextRequest,
  { params }: { params: { id: string } }
) {
  const db = getDb();

  const bean = db
    .prepare("SELECT id, is_frozen FROM beans WHERE id = ?")
    .get(params.id) as any;
  if (!bean) {
    return NextResponse.json({ error: "Bean not found" }, { status: 404 });
  }

  const isFrozen = Boolean(bean.is_frozen);
  const newState = !isFrozen;
  const eventType = newState ? "freeze" : "thaw";
  const today = getToday();

  const toggleTx = db.transaction(() => {
    db.prepare("UPDATE beans SET is_frozen = ?, planned_thaw_date = NULL, freeze_after_grams = NULL WHERE id = ?").run(
      newState ? 1 : 0,
      params.id
    );
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, ?, ?)"
    ).run(params.id, eventType, today);
  });

  toggleTx();

  return NextResponse.json({ success: true, is_frozen: newState });
}
