import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import { parseBcZip } from "@/lib/bc-json-parser";

export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData();
    const file = formData.get("file") as File | null;

    if (!file) {
      return NextResponse.json({ error: "No file provided" }, { status: 400 });
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    const { beans, brews, freezeEvents, errors } = parseBcZip(buffer);

    const db = getDb();

    const upsertBean = db.prepare(`
      INSERT INTO beans (id, name, roaster, roast_date, weight_grams, cost, flavour_profile, country, region, variety, processing, archived, is_frozen)
      VALUES (@id, @name, @roaster, @roast_date, @weight_grams, @cost, @flavour_profile, @country, @region, @variety, @processing, @archived, @is_frozen)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        roaster = excluded.roaster,
        roast_date = excluded.roast_date,
        weight_grams = excluded.weight_grams,
        cost = excluded.cost,
        flavour_profile = excluded.flavour_profile,
        country = excluded.country,
        region = excluded.region,
        variety = excluded.variety,
        processing = excluded.processing,
        archived = excluded.archived,
        is_frozen = MAX(beans.is_frozen, excluded.is_frozen)
    `);

    const deleteBrewsForBean = db.prepare("DELETE FROM brews WHERE bean_id = ?");

    const insertBrew = db.prepare(`
      INSERT INTO brews (bean_id, ground_coffee_grams, creation_date, bean_age_days, rating)
      VALUES (@bean_id, @ground_coffee_grams, @creation_date, @bean_age_days, @rating)
    `);

    const checkFreezeEvent = db.prepare(
      "SELECT COUNT(*) as count FROM freeze_events WHERE bean_id = ? AND event_type = 'freeze'"
    );

    const insertFreezeEvent = db.prepare(`
      INSERT INTO freeze_events (bean_id, event_type, event_date)
      VALUES (?, 'freeze', ?)
    `);

    const importTransaction = db.transaction(() => {
      let beansImported = 0;
      let brewsImported = 0;

      for (const bean of beans) {
        upsertBean.run({
          ...bean,
          archived: bean.archived ? 1 : 0,
          is_frozen: bean.is_frozen ? 1 : 0,
        });
        beansImported++;
      }

      // Sync freeze events for currently frozen beans
      for (const fe of freezeEvents) {
        const existing = checkFreezeEvent.get(fe.bean_id) as { count: number };
        if (existing.count === 0) {
          insertFreezeEvent.run(fe.bean_id, fe.frozen_date);
        }
      }

      // Collect unique bean IDs from brews and delete existing brews for those beans
      const beanIdsWithBrews = new Set(brews.map((b) => b.bean_id));
      for (const beanId of beanIdsWithBrews) {
        deleteBrewsForBean.run(beanId);
      }

      for (const brew of brews) {
        insertBrew.run(brew);
        brewsImported++;
      }

      return { beansImported, brewsImported };
    });

    const result = importTransaction();

    return NextResponse.json({
      success: true,
      beansImported: result.beansImported,
      brewsImported: result.brewsImported,
      errors: errors.length > 0 ? errors : undefined,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Unknown error during import";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
