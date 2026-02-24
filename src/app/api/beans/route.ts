import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import { autoThawBeans } from "@/lib/auto-thaw";

export async function GET(request: NextRequest) {
  const db = getDb();
  const today = new Date().toISOString().split("T")[0];
  autoThawBeans(db, today);

  const showArchived =
    request.nextUrl.searchParams.get("archived") === "true";

  const beans = db
    .prepare(
      `
    SELECT
      b.*,
      COALESCE(b.rest_days, rd.rest_days, CAST((SELECT value FROM settings WHERE key = 'default_rest_days') AS INTEGER)) as effective_rest_days,
      COALESCE((SELECT SUM(br.ground_coffee_grams) FROM brews br WHERE br.bean_id = b.id), 0) as total_brewed_grams,
      COALESCE((SELECT SUM(s.grams) FROM splits s WHERE s.bean_id = b.id), 0) as total_split_grams
    FROM beans b
    LEFT JOIN roaster_defaults rd ON rd.roaster = b.roaster
    WHERE b.archived = ?
    ORDER BY
      CASE WHEN b.display_order IS NOT NULL THEN 0 ELSE 1 END,
      b.display_order,
      b.roast_date
  `
    )
    .all(showArchived ? 1 : 0)
    .map((row: any) => ({
      ...row,
      archived: Boolean(row.archived),
      is_frozen: Boolean(row.is_frozen),
      remaining_grams:
        row.weight_grams - row.total_brewed_grams - row.total_split_grams,
      ready_date: row.roast_date
        ? (() => {
            const d = new Date(row.roast_date);
            d.setDate(d.getDate() + row.effective_rest_days);
            return d.toISOString().split("T")[0];
          })()
        : null,
    }));

  return NextResponse.json(beans);
}
