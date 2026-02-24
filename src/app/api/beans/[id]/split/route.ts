import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";

export async function POST(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  const body = await request.json();
  const db = getDb();

  const bean = db
    .prepare("SELECT id, weight_grams FROM beans WHERE id = ?")
    .get(params.id) as any;
  if (!bean) {
    return NextResponse.json({ error: "Bean not found" }, { status: 404 });
  }

  if (!body.grams || body.grams <= 0) {
    return NextResponse.json(
      { error: "Grams must be positive" },
      { status: 400 }
    );
  }

  db.prepare(
    `INSERT INTO splits (bean_id, grams, recipient, split_date, notes)
     VALUES (?, ?, ?, ?, ?)`
  ).run(
    params.id,
    body.grams,
    body.recipient || "",
    body.split_date || new Date().toISOString().split("T")[0],
    body.notes || null
  );

  return NextResponse.json({ success: true });
}
