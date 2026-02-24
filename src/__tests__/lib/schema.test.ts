import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";

describe("schema", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
  });

  it("creates all required tables", () => {
    initializeSchema(db);

    const tables = db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
      )
      .all()
      .map((r: any) => r.name);

    expect(tables).toContain("settings");
    expect(tables).toContain("beans");
    expect(tables).toContain("brews");
    expect(tables).toContain("roaster_defaults");
    expect(tables).toContain("freeze_events");
    expect(tables).toContain("skip_days");
  });

  it("inserts default settings", () => {
    initializeSchema(db);

    const settings = db.prepare("SELECT * FROM settings").all() as any[];
    const settingsMap = Object.fromEntries(
      settings.map((s) => [s.key, s.value])
    );

    expect(settingsMap.daily_consumption_grams).toBe("45");
    expect(settingsMap.default_rest_days).toBe("30");
  });

  it("is idempotent (can run twice without error)", () => {
    initializeSchema(db);
    initializeSchema(db);

    const settings = db.prepare("SELECT * FROM settings").all();
    expect(settings).toHaveLength(2);
  });

  it("creates expected indexes", () => {
    initializeSchema(db);

    const indexes = db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'"
      )
      .all()
      .map((r: any) => r.name);

    expect(indexes).toContain("idx_brews_bean_id");
    expect(indexes).toContain("idx_freeze_events_bean_id");
  });

  it("has planned_thaw_date column on beans table", () => {
    initializeSchema(db);

    const columns = db
      .prepare("PRAGMA table_info(beans)")
      .all()
      .map((r: any) => r.name);

    expect(columns).toContain("planned_thaw_date");
  });

  it("enforces freeze_events event_type check constraint", () => {
    initializeSchema(db);

    db.prepare(
      "INSERT INTO beans (id, name) VALUES ('test-bean', 'Test')"
    ).run();

    expect(() => {
      db.prepare(
        "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('test-bean', 'invalid', '2026-01-01')"
      ).run();
    }).toThrow();
  });
});
