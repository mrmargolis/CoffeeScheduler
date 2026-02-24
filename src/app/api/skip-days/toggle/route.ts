import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";

interface SkipRow {
  id: number;
  start_date: string;
  end_date: string;
  reason: string | null;
}

/** Add one day to an ISO date string. */
function addDays(iso: string, n: number): string {
  const d = new Date(iso + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().split("T")[0];
}

export async function POST(request: NextRequest) {
  const db = getDb();
  const body = await request.json();
  const { date } = body;

  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return NextResponse.json(
      { error: "date is required (YYYY-MM-DD)" },
      { status: 400 }
    );
  }

  // Find any range that contains this date
  const containingRange = db
    .prepare(
      "SELECT * FROM skip_days WHERE start_date <= ? AND end_date >= ?"
    )
    .get(date, date) as SkipRow | undefined;

  if (containingRange) {
    // Toggle OFF: remove this date from the range
    const { id, start_date, end_date, reason } = containingRange;

    if (start_date === date && end_date === date) {
      // Single-day range — just delete it
      db.prepare("DELETE FROM skip_days WHERE id = ?").run(id);
    } else if (start_date === date) {
      // Date is at the start — advance start_date
      db.prepare("UPDATE skip_days SET start_date = ? WHERE id = ?").run(
        addDays(date, 1),
        id
      );
    } else if (end_date === date) {
      // Date is at the end — pull back end_date
      db.prepare("UPDATE skip_days SET end_date = ? WHERE id = ?").run(
        addDays(date, -1),
        id
      );
    } else {
      // Date is in the middle — split into two ranges
      const beforeEnd = addDays(date, -1);
      const afterStart = addDays(date, 1);
      db.prepare("DELETE FROM skip_days WHERE id = ?").run(id);
      db.prepare(
        "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)"
      ).run(start_date, beforeEnd, reason);
      db.prepare(
        "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)"
      ).run(afterStart, end_date, reason);
    }

    return NextResponse.json({ skipped: false });
  }

  // Toggle ON: add this date as a skip day, merging with adjacent ranges
  const prevDay = addDays(date, -1);
  const nextDay = addDays(date, 1);

  const prevRange = db
    .prepare("SELECT * FROM skip_days WHERE end_date = ?")
    .get(prevDay) as SkipRow | undefined;

  const nextRange = db
    .prepare("SELECT * FROM skip_days WHERE start_date = ?")
    .get(nextDay) as SkipRow | undefined;

  if (prevRange && nextRange) {
    // Merge both adjacent ranges into one
    db.prepare("UPDATE skip_days SET end_date = ? WHERE id = ?").run(
      nextRange.end_date,
      prevRange.id
    );
    db.prepare("DELETE FROM skip_days WHERE id = ?").run(nextRange.id);
  } else if (prevRange) {
    // Extend previous range forward
    db.prepare("UPDATE skip_days SET end_date = ? WHERE id = ?").run(
      date,
      prevRange.id
    );
  } else if (nextRange) {
    // Extend next range backward
    db.prepare("UPDATE skip_days SET start_date = ? WHERE id = ?").run(
      date,
      nextRange.id
    );
  } else {
    // Insert new single-day range
    db.prepare(
      "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)"
    ).run(date, date, null);
  }

  return NextResponse.json({ skipped: true });
}
