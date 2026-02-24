import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";

describe("beans", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
    initializeSchema(db);

    // Insert test beans
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived)
       VALUES ('bean-1', 'Ethiopia', 'Square Mile', '2026-01-15', 250, 0)`
    ).run();
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived)
       VALUES ('bean-2', 'Colombia', 'Tim Wendelboe', '2026-01-20', 250, 0)`
    ).run();
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived)
       VALUES ('bean-3', 'Brazil', 'Local', '2025-06-01', 250, 1)`
    ).run();
  });

  it("lists active beans with computed fields", () => {
    // Add some brews
    db.prepare(
      "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('bean-1', 15, '2026-02-15')"
    ).run();
    db.prepare(
      "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('bean-1', 15, '2026-02-16')"
    ).run();

    const beans = db
      .prepare(
        `SELECT b.*,
          COALESCE((SELECT SUM(br.ground_coffee_grams) FROM brews br WHERE br.bean_id = b.id), 0) as total_brewed_grams
        FROM beans b WHERE b.archived = 0`
      )
      .all() as any[];

    expect(beans).toHaveLength(2);
    const eth = beans.find((b) => b.id === "bean-1");
    expect(eth.total_brewed_grams).toBe(30);
    expect(eth.weight_grams - eth.total_brewed_grams).toBe(220);
  });

  it("updates user-managed fields", () => {
    db.prepare(
      "UPDATE beans SET rest_days = 21, notes = 'Great' WHERE id = 'bean-1'"
    ).run();

    const bean = db
      .prepare("SELECT * FROM beans WHERE id = 'bean-1'")
      .get() as any;
    expect(bean.rest_days).toBe(21);
    expect(bean.notes).toBe("Great");
  });

  it("toggles freeze state and logs events", () => {
    // Freeze
    db.prepare("UPDATE beans SET is_frozen = 1 WHERE id = 'bean-1'").run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('bean-1', 'freeze', '2026-02-01')"
    ).run();

    let bean = db
      .prepare("SELECT is_frozen FROM beans WHERE id = 'bean-1'")
      .get() as any;
    expect(bean.is_frozen).toBe(1);

    // Thaw
    db.prepare("UPDATE beans SET is_frozen = 0 WHERE id = 'bean-1'").run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('bean-1', 'thaw', '2026-02-10')"
    ).run();

    bean = db
      .prepare("SELECT is_frozen FROM beans WHERE id = 'bean-1'")
      .get() as any;
    expect(bean.is_frozen).toBe(0);

    const events = db
      .prepare(
        "SELECT * FROM freeze_events WHERE bean_id = 'bean-1' ORDER BY event_date"
      )
      .all() as any[];
    expect(events).toHaveLength(2);
    expect(events[0].event_type).toBe("freeze");
    expect(events[1].event_type).toBe("thaw");
  });

  it("computes effective rest days with roaster default fallback", () => {
    // No bean override, no roaster default → global default (30)
    const bean1 = db
      .prepare(
        `SELECT COALESCE(b.rest_days, rd.rest_days,
          CAST((SELECT value FROM settings WHERE key = 'default_rest_days') AS INTEGER)) as effective
        FROM beans b
        LEFT JOIN roaster_defaults rd ON rd.roaster = b.roaster
        WHERE b.id = 'bean-1'`
      )
      .get() as any;
    expect(bean1.effective).toBe(30);

    // Add roaster default
    db.prepare(
      "INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Square Mile', 28)"
    ).run();

    const bean1b = db
      .prepare(
        `SELECT COALESCE(b.rest_days, rd.rest_days,
          CAST((SELECT value FROM settings WHERE key = 'default_rest_days') AS INTEGER)) as effective
        FROM beans b
        LEFT JOIN roaster_defaults rd ON rd.roaster = b.roaster
        WHERE b.id = 'bean-1'`
      )
      .get() as any;
    expect(bean1b.effective).toBe(28);

    // Bean override takes precedence
    db.prepare("UPDATE beans SET rest_days = 14 WHERE id = 'bean-1'").run();

    const bean1c = db
      .prepare(
        `SELECT COALESCE(b.rest_days, rd.rest_days,
          CAST((SELECT value FROM settings WHERE key = 'default_rest_days') AS INTEGER)) as effective
        FROM beans b
        LEFT JOIN roaster_defaults rd ON rd.roaster = b.roaster
        WHERE b.id = 'bean-1'`
      )
      .get() as any;
    expect(bean1c.effective).toBe(14);
  });

  it("orders beans by display_order then roast_date", () => {
    db.prepare(
      "UPDATE beans SET display_order = 2 WHERE id = 'bean-1'"
    ).run();
    db.prepare(
      "UPDATE beans SET display_order = 1 WHERE id = 'bean-2'"
    ).run();

    const beans = db
      .prepare(
        `SELECT id FROM beans WHERE archived = 0
         ORDER BY
           CASE WHEN display_order IS NOT NULL THEN 0 ELSE 1 END,
           display_order,
           roast_date`
      )
      .all() as any[];

    expect(beans[0].id).toBe("bean-2");
    expect(beans[1].id).toBe("bean-1");
  });
});
