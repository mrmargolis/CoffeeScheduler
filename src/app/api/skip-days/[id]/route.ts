import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const db = getDb();
  const { id } = await params;
  const body = await request.json();

  const existing = db
    .prepare("SELECT * FROM skip_days WHERE id = ?")
    .get(Number(id));

  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const { start_date, end_date, reason } = body;

  if (start_date && end_date && end_date < start_date) {
    return NextResponse.json(
      { error: "end_date must not be before start_date" },
      { status: 400 }
    );
  }

  const updates: string[] = [];
  const values: any[] = [];

  if (start_date !== undefined) {
    updates.push("start_date = ?");
    values.push(start_date);
  }
  if (end_date !== undefined) {
    updates.push("end_date = ?");
    values.push(end_date);
  }
  if (reason !== undefined) {
    updates.push("reason = ?");
    values.push(reason);
  }

  if (updates.length > 0) {
    values.push(Number(id));
    db.prepare(`UPDATE skip_days SET ${updates.join(", ")} WHERE id = ?`).run(
      ...values
    );
  }

  const updated = db
    .prepare("SELECT * FROM skip_days WHERE id = ?")
    .get(Number(id));

  return NextResponse.json(updated);
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const db = getDb();
  const { id } = await params;

  const existing = db
    .prepare("SELECT * FROM skip_days WHERE id = ?")
    .get(Number(id));

  if (!existing) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  db.prepare("DELETE FROM skip_days WHERE id = ?").run(Number(id));

  return NextResponse.json({ success: true });
}
