import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";

export async function GET() {
  const db = getDb();
  const rows = db
    .prepare("SELECT * FROM skip_days ORDER BY start_date")
    .all();
  return NextResponse.json(rows);
}

export async function POST(request: NextRequest) {
  const db = getDb();
  const body = await request.json();
  const { start_date, end_date, reason } = body;

  if (!start_date || !end_date) {
    return NextResponse.json(
      { error: "start_date and end_date are required" },
      { status: 400 }
    );
  }

  if (end_date < start_date) {
    return NextResponse.json(
      { error: "end_date must not be before start_date" },
      { status: 400 }
    );
  }

  const result = db
    .prepare(
      "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)"
    )
    .run(start_date, end_date, reason || null);

  const created = db
    .prepare("SELECT * FROM skip_days WHERE id = ?")
    .get(result.lastInsertRowid);

  return NextResponse.json(created, { status: 201 });
}
