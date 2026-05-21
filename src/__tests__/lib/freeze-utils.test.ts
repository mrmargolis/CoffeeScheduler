import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";
import { computeFrozenDays, effectiveAge } from "@/lib/freeze-utils";

describe("effectiveAge", () => {
  it("returns calendar age minus frozen days", () => {
    expect(effectiveAge("2026-01-01", "2026-04-01", 30)).toBe(60);
  });

  it("returns calendar age when frozen_days is 0", () => {
    expect(effectiveAge("2026-01-01", "2026-04-01", 0)).toBe(90);
  });

  it("returns null when roast date is null", () => {
    expect(effectiveAge(null, "2026-04-01", 0)).toBeNull();
  });

  it("floors at 0 to handle drift", () => {
    expect(effectiveAge("2026-01-01", "2026-01-10", 30)).toBe(0);
  });
});

describe("computeFrozenDays", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
    initializeSchema(db);

    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived)
       VALUES ('b1', 'Ethiopia', 'Square Mile', '2026-01-01', 250, 0)`
    ).run();
  });

  it("returns 0 (empty map entry) for beans with no freeze events", () => {
    const result = computeFrozenDays(db, "2026-03-01");
    expect(result.get("b1")).toBeUndefined();
  });

  it("sums one balanced freeze/thaw pair", () => {
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-10')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'thaw', '2026-02-09')"
    ).run();

    const result = computeFrozenDays(db, "2026-03-01");
    expect(result.get("b1")).toBe(30);
  });

  it("sums multiple freeze/thaw cycles", () => {
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-10')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'thaw', '2026-01-20')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-02-01')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'thaw', '2026-02-15')"
    ).run();

    const result = computeFrozenDays(db, "2026-03-01");
    expect(result.get("b1")).toBe(24); // 10 + 14
  });

  it("counts active freeze (no thaw event) up to today", () => {
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-10')"
    ).run();
    db.prepare("UPDATE beans SET is_frozen = 1 WHERE id = 'b1'").run();

    const result = computeFrozenDays(db, "2026-02-09");
    expect(result.get("b1")).toBe(30);
  });

  it("counts active freeze up to planned_thaw_date when set", () => {
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-10')"
    ).run();
    db.prepare(
      "UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-02-15' WHERE id = 'b1'"
    ).run();

    const result = computeFrozenDays(db, "2026-02-01");
    expect(result.get("b1")).toBe(36); // Jan 10 → Feb 15
  });

  it("combines a completed freeze cycle with a still-active freeze", () => {
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-10')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'thaw', '2026-01-20')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-02-01')"
    ).run();
    db.prepare("UPDATE beans SET is_frozen = 1 WHERE id = 'b1'").run();

    const result = computeFrozenDays(db, "2026-02-15");
    expect(result.get("b1")).toBe(24); // 10 + 14
  });

  it("ignores stray thaw without a matching freeze", () => {
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'thaw', '2026-01-20')"
    ).run();

    const result = computeFrozenDays(db, "2026-03-01");
    expect(result.get("b1")).toBeUndefined();
  });

  it("computes per-bean independently", () => {
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived)
       VALUES ('b2', 'Colombia', 'Tim Wendelboe', '2026-01-15', 250, 0)`
    ).run();

    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-10')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'thaw', '2026-01-25')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b2', 'freeze', '2026-02-01')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b2', 'thaw', '2026-02-08')"
    ).run();

    const result = computeFrozenDays(db, "2026-03-01");
    expect(result.get("b1")).toBe(15);
    expect(result.get("b2")).toBe(7);
  });
});
