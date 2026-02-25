import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";
import { queryBeans, queryBean } from "@/lib/bean-queries";

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

    const beans = queryBeans(db, { archived: false });

    expect(beans).toHaveLength(2);
    const eth = beans.find((b) => b.id === "bean-1")!;
    expect(eth.total_brewed_grams).toBe(30);
    expect(eth.remaining_grams).toBe(220);
  });

  it("updates user-managed fields", () => {
    db.prepare(
      "UPDATE beans SET rest_days = 21, notes = 'Great' WHERE id = 'bean-1'"
    ).run();

    const bean = queryBean(db, "bean-1")!;
    expect(bean.rest_days).toBe(21);
    expect(bean.notes).toBe("Great");
  });

  it("toggles freeze state and logs events", () => {
    // Freeze
    db.prepare("UPDATE beans SET is_frozen = 1 WHERE id = 'bean-1'").run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('bean-1', 'freeze', '2026-02-01')"
    ).run();

    let bean = queryBean(db, "bean-1")!;
    expect(bean.is_frozen).toBe(true);

    // Thaw
    db.prepare("UPDATE beans SET is_frozen = 0 WHERE id = 'bean-1'").run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('bean-1', 'thaw', '2026-02-10')"
    ).run();

    bean = queryBean(db, "bean-1")!;
    expect(bean.is_frozen).toBe(false);

    const events = db
      .prepare(
        "SELECT * FROM freeze_events WHERE bean_id = 'bean-1' ORDER BY event_date"
      )
      .all() as any[];
    expect(events).toHaveLength(2);
    expect(events[0].event_type).toBe("freeze");
    expect(events[1].event_type).toBe("thaw");
  });

  it("orders beans by display_order then roast_date", () => {
    db.prepare(
      "UPDATE beans SET display_order = 2 WHERE id = 'bean-1'"
    ).run();
    db.prepare(
      "UPDATE beans SET display_order = 1 WHERE id = 'bean-2'"
    ).run();

    const beans = queryBeans(db, { archived: false });

    expect(beans[0].id).toBe("bean-2");
    expect(beans[1].id).toBe("bean-1");
  });
});
