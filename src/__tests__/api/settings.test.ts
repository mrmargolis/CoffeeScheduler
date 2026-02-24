import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";

describe("settings", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
    initializeSchema(db);
  });

  it("has correct default settings", () => {
    const rows = db.prepare("SELECT key, value FROM settings").all() as any[];
    const settings = Object.fromEntries(rows.map((r) => [r.key, r.value]));
    expect(settings.daily_consumption_grams).toBe("45");
    expect(settings.default_rest_days).toBe("30");
  });

  it("can update settings", () => {
    db.prepare(
      "INSERT OR REPLACE INTO settings (key, value) VALUES ('daily_consumption_grams', '50')"
    ).run();

    const row = db
      .prepare("SELECT value FROM settings WHERE key = 'daily_consumption_grams'")
      .get() as any;
    expect(row.value).toBe("50");
  });

  it("can manage roaster defaults", () => {
    db.prepare(
      "INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Square Mile', 28)"
    ).run();
    db.prepare(
      "INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Tim Wendelboe', 21)"
    ).run();

    const defaults = db
      .prepare("SELECT * FROM roaster_defaults ORDER BY roaster")
      .all() as any[];
    expect(defaults).toHaveLength(2);
    expect(defaults[0].roaster).toBe("Square Mile");
    expect(defaults[0].rest_days).toBe(28);
  });

  it("upserts roaster defaults", () => {
    db.prepare(
      "INSERT OR REPLACE INTO roaster_defaults (roaster, rest_days) VALUES ('Square Mile', 28)"
    ).run();
    db.prepare(
      "INSERT OR REPLACE INTO roaster_defaults (roaster, rest_days) VALUES ('Square Mile', 35)"
    ).run();

    const defaults = db
      .prepare("SELECT * FROM roaster_defaults")
      .all() as any[];
    expect(defaults).toHaveLength(1);
    expect(defaults[0].rest_days).toBe(35);
  });
});
