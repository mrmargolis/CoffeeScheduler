import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";

export async function GET() {
  const db = getDb();
  const rows = db.prepare("SELECT key, value FROM settings").all() as {
    key: string;
    value: string;
  }[];
  const settings = Object.fromEntries(rows.map((r) => [r.key, r.value]));

  // Include roaster defaults
  const roasterDefaults = db
    .prepare("SELECT roaster, rest_days FROM roaster_defaults ORDER BY roaster")
    .all();

  return NextResponse.json({
    daily_consumption_grams: Number(settings.daily_consumption_grams) || 45,
    default_rest_days: Number(settings.default_rest_days) || 30,
    roaster_defaults: roasterDefaults,
  });
}

export async function PATCH(request: NextRequest) {
  const body = await request.json();
  const db = getDb();

  const updateSetting = db.prepare(
    "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
  );

  if (body.daily_consumption_grams !== undefined) {
    updateSetting.run(
      "daily_consumption_grams",
      String(body.daily_consumption_grams)
    );
  }
  if (body.default_rest_days !== undefined) {
    updateSetting.run("default_rest_days", String(body.default_rest_days));
  }

  if (body.roaster_defaults) {
    const upsertRoaster = db.prepare(
      "INSERT OR REPLACE INTO roaster_defaults (roaster, rest_days) VALUES (?, ?)"
    );
    const deleteRoaster = db.prepare(
      "DELETE FROM roaster_defaults WHERE roaster = ?"
    );

    for (const rd of body.roaster_defaults) {
      if (rd.rest_days === null) {
        deleteRoaster.run(rd.roaster);
      } else {
        upsertRoaster.run(rd.roaster, rd.rest_days);
      }
    }
  }

  return NextResponse.json({ success: true });
}
