import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import { autoThawBeans } from "@/lib/auto-thaw";
import { queryBean } from "@/lib/bean-queries";

export async function GET(
  _request: NextRequest,
  { params }: { params: { id: string } }
) {
  const db = getDb();
  const today = new Date().toISOString().split("T")[0];
  autoThawBeans(db, today);

  const bean = queryBean(db, params.id);

  if (!bean) {
    return NextResponse.json({ error: "Bean not found" }, { status: 404 });
  }

  const freezeEvents = db
    .prepare(
      "SELECT * FROM freeze_events WHERE bean_id = ? ORDER BY event_date"
    )
    .all(params.id);

  const recentBrews = db
    .prepare(
      "SELECT * FROM brews WHERE bean_id = ? ORDER BY creation_date DESC LIMIT 10"
    )
    .all(params.id);

  return NextResponse.json({
    ...bean,
    freeze_events: freezeEvents,
    recent_brews: recentBrews,
  });
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  const body = await request.json();
  const db = getDb();

  const bean = db.prepare("SELECT id FROM beans WHERE id = ?").get(params.id);
  if (!bean) {
    return NextResponse.json({ error: "Bean not found" }, { status: 404 });
  }

  const updates: string[] = [];
  const values: any[] = [];

  if (body.rest_days !== undefined) {
    updates.push("rest_days = ?");
    values.push(body.rest_days);
  }
  if (body.notes !== undefined) {
    updates.push("notes = ?");
    values.push(body.notes);
  }
  if (body.display_order !== undefined) {
    updates.push("display_order = ?");
    values.push(body.display_order);
  }
  if (body.roast_date !== undefined) {
    updates.push("roast_date = ?");
    values.push(body.roast_date);
  }
  if (body.planned_thaw_date !== undefined) {
    updates.push("planned_thaw_date = ?");
    values.push(body.planned_thaw_date);
  }

  if (updates.length > 0) {
    values.push(params.id);
    db.prepare(
      `UPDATE beans SET ${updates.join(", ")} WHERE id = ?`
    ).run(...values);
  }

  return NextResponse.json({ success: true });
}
