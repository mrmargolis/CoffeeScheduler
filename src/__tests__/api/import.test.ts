import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import AdmZip from "adm-zip";
import { initializeSchema } from "@/lib/schema";
import { parseBcZip } from "@/lib/bc-json-parser";
import type { FreezeInfo } from "@/lib/bc-json-parser";

function createTestZip(
  beans: any[] = [],
  brews: any[] = [],
  extraBrewFiles?: Record<string, any[]>
): Buffer {
  const zip = new AdmZip();
  const mainData: any = { BEANS: beans, BREWS: brews };
  zip.addFile("Beanconqueror.json", Buffer.from(JSON.stringify(mainData)));
  if (extraBrewFiles) {
    for (const [name, data] of Object.entries(extraBrewFiles)) {
      zip.addFile(name, Buffer.from(JSON.stringify(data)));
    }
  }
  return zip.toBuffer();
}

function makeBean(overrides: Record<string, any> = {}) {
  return {
    name: "Test Bean",
    roaster: "Test Roaster",
    roastingDate: "2026-01-15T00:00:00.000Z",
    weight: 250,
    cost: 0,
    finished: false,
    bean_information: [],
    config: { uuid: "uuid-1", unix_timestamp: 1700000000 },
    ...overrides,
  };
}

function makeBrew(overrides: Record<string, any> = {}) {
  return {
    bean: "uuid-1",
    grind_weight: 15,
    rating: 4,
    config: { uuid: "brew-1", unix_timestamp: 1706745600 },
    ...overrides,
  };
}

function simulateImport(db: Database.Database, buffer: Buffer) {
  const { beans, brews, freezeEvents, errors } = parseBcZip(buffer);

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

  const deleteBrewsForBean = db.prepare(
    "DELETE FROM brews WHERE bean_id = ?"
  );
  const insertBrew = db.prepare(`
    INSERT INTO brews (bean_id, ground_coffee_grams, creation_date, bean_age_days, rating)
    VALUES (@bean_id, @ground_coffee_grams, @creation_date, @bean_age_days, @rating)
  `);

  const checkFreezeEvent = db.prepare(
    "SELECT COUNT(*) as count FROM freeze_events WHERE bean_id = ? AND event_type = 'freeze'"
  );
  const insertFreezeEvent = db.prepare(
    "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, 'freeze', ?)"
  );

  const importTx = db.transaction(() => {
    for (const bean of beans) {
      upsertBean.run({ ...bean, archived: bean.archived ? 1 : 0, is_frozen: bean.is_frozen ? 1 : 0 });
    }

    for (const fe of freezeEvents) {
      const existing = checkFreezeEvent.get(fe.bean_id) as { count: number };
      if (existing.count === 0) {
        insertFreezeEvent.run(fe.bean_id, fe.frozen_date);
      }
    }

    const beanIds = new Set(brews.map((b) => b.bean_id));
    for (const id of beanIds) {
      deleteBrewsForBean.run(id);
    }
    for (const brew of brews) {
      insertBrew.run(brew);
    }
  });

  importTx();
  return { beansImported: beans.length, brewsImported: brews.length, errors };
}

describe("import logic", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
    initializeSchema(db);
  });

  it("imports beans and brews into the database", () => {
    const buffer = createTestZip(
      [makeBean()],
      [makeBrew()]
    );

    const result = simulateImport(db, buffer);
    expect(result.beansImported).toBe(1);
    expect(result.brewsImported).toBe(1);

    const beans = db.prepare("SELECT * FROM beans").all() as any[];
    expect(beans).toHaveLength(1);
    expect(beans[0].name).toBe("Test Bean");
    expect(beans[0].roast_date).toBe("2026-01-15");

    const brews = db.prepare("SELECT * FROM brews").all() as any[];
    expect(brews).toHaveLength(1);
    expect(brews[0].ground_coffee_grams).toBe(15);
  });

  it("preserves user-managed fields on re-import", () => {
    const buffer1 = createTestZip([makeBean({ name: "Original Name" })]);
    simulateImport(db, buffer1);

    db.prepare(
      "UPDATE beans SET rest_days = 21, notes = 'Great bean', display_order = 1 WHERE id = 'uuid-1'"
    ).run();

    const buffer2 = createTestZip([makeBean({ name: "Updated Name" })]);
    simulateImport(db, buffer2);

    const bean = db
      .prepare("SELECT * FROM beans WHERE id = 'uuid-1'")
      .get() as any;
    expect(bean.name).toBe("Updated Name");
    expect(bean.rest_days).toBe(21);
    expect(bean.notes).toBe("Great bean");
    expect(bean.display_order).toBe(1);
  });

  it("imports frozen status from ZIP", () => {
    const buffer = createTestZip([
      makeBean({
        frozenId: "abc123",
        frozenDate: "2026-01-20T10:00:00.000Z",
        unfrozenDate: "",
      }),
    ]);

    simulateImport(db, buffer);

    const bean = db.prepare("SELECT * FROM beans WHERE id = 'uuid-1'").get() as any;
    expect(bean.is_frozen).toBe(1);
  });

  it("creates freeze events for frozen beans on import", () => {
    const buffer = createTestZip([
      makeBean({
        frozenId: "abc123",
        frozenDate: "2026-01-20T10:00:00.000Z",
        unfrozenDate: "",
      }),
    ]);

    simulateImport(db, buffer);

    const events = db
      .prepare("SELECT * FROM freeze_events WHERE bean_id = 'uuid-1'")
      .all() as any[];
    expect(events).toHaveLength(1);
    expect(events[0].event_type).toBe("freeze");
    expect(events[0].event_date).toBe("2026-01-20");
  });

  it("does not duplicate freeze events on re-import", () => {
    const buffer = createTestZip([
      makeBean({
        frozenId: "abc123",
        frozenDate: "2026-01-20T10:00:00.000Z",
        unfrozenDate: "",
      }),
    ]);

    simulateImport(db, buffer);
    simulateImport(db, buffer);

    const events = db
      .prepare("SELECT * FROM freeze_events WHERE bean_id = 'uuid-1'")
      .all() as any[];
    expect(events).toHaveLength(1);
  });

  it("preserves frozen status on re-import when locally frozen", () => {
    const buffer1 = createTestZip([makeBean()]);
    simulateImport(db, buffer1);

    db.prepare("UPDATE beans SET is_frozen = 1 WHERE id = 'uuid-1'").run();

    // Re-import: ZIP says not frozen, but local freeze should be preserved
    const buffer2 = createTestZip([makeBean({ name: "Bean Updated" })]);
    simulateImport(db, buffer2);

    const bean = db.prepare("SELECT * FROM beans WHERE id = 'uuid-1'").get() as any;
    expect(bean.name).toBe("Bean Updated");
    expect(bean.is_frozen).toBe(1);
  });

  it("replaces brews on re-import", () => {
    const buffer1 = createTestZip(
      [makeBean()],
      [
        makeBrew({ config: { uuid: "br1", unix_timestamp: 1706745600 } }),
        makeBrew({ config: { uuid: "br2", unix_timestamp: 1706832000 } }),
      ]
    );
    simulateImport(db, buffer1);
    expect(db.prepare("SELECT COUNT(*) as c FROM brews").get() as any).toEqual({
      c: 2,
    });

    const buffer2 = createTestZip(
      [makeBean()],
      [
        makeBrew({ config: { uuid: "br1", unix_timestamp: 1706745600 } }),
        makeBrew({ config: { uuid: "br2", unix_timestamp: 1706832000 } }),
        makeBrew({ config: { uuid: "br3", unix_timestamp: 1706918400 } }),
      ]
    );
    simulateImport(db, buffer2);
    expect(db.prepare("SELECT COUNT(*) as c FROM brews").get() as any).toEqual({
      c: 3,
    });
  });
});
