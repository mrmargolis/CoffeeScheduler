import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";

export async function GET() {
  const db = getDb();
  const rows = db
    .prepare("SELECT * FROM consumption_overrides ORDER BY start_date")
    .all();
  return NextResponse.json(rows);
}

export async function POST(request: NextRequest) {
  const db = getDb();
  const body = await request.json();
  const { start_date, end_date, daily_grams, dose_size_grams } = body;

  if (!start_date || !end_date || daily_grams == null || dose_size_grams == null) {
    return NextResponse.json(
      { error: "start_date, end_date, daily_grams, and dose_size_grams are required" },
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
      "INSERT INTO consumption_overrides (start_date, end_date, daily_grams, dose_size_grams) VALUES (?, ?, ?, ?)"
    )
    .run(start_date, end_date, daily_grams, dose_size_grams);

  const created = db
    .prepare("SELECT * FROM consumption_overrides WHERE id = ?")
    .get(result.lastInsertRowid);

  return NextResponse.json(created, { status: 201 });
}
