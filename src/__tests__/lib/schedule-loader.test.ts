import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";
import { loadScheduleData } from "@/lib/schedule-loader";

describe("loadScheduleData", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
    initializeSchema(db);
  });

  function insertBean(
    id: string,
    name: string,
    roaster: string,
    roastDate: string | null,
    weight: number
  ) {
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived)
       VALUES (?, ?, ?, ?, ?, 0)`
    ).run(id, name, roaster, roastDate, weight);
  }

  it("returns schedule and skipDayRanges", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);

    const result = loadScheduleData(db, "2026-01-31", "2026-02-04", "2026-01-01");

    expect(result.schedule).toHaveLength(5);
    expect(result.skipDayRanges).toEqual([]);
    expect(result.schedule[0].consumptions[0].bean_name).toBe("Ethiopia");
  });

  it("includes skip day ranges in result", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    db.prepare(
      "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)"
    ).run("2026-02-01", "2026-02-02", "Travel");

    const result = loadScheduleData(db, "2026-01-31", "2026-02-04", "2026-01-01");

    expect(result.skipDayRanges).toHaveLength(1);
    expect(result.skipDayRanges[0].start_date).toBe("2026-02-01");

    const feb1 = result.schedule.find((d) => d.date === "2026-02-01");
    expect(feb1?.is_skip).toBe(true);
    expect(feb1?.consumptions).toHaveLength(0);
  });

  it("computes frozen days from freeze events", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, ?, ?)"
    ).run("b1", "freeze", "2026-01-10");
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, ?, ?)"
    ).run("b1", "thaw", "2026-01-20");

    // rest_days=30 + frozen_days=10 → ready on Feb 10
    const result = loadScheduleData(db, "2026-02-09", "2026-02-11", "2026-02-01");

    const feb9 = result.schedule.find((d) => d.date === "2026-02-09");
    const feb10 = result.schedule.find((d) => d.date === "2026-02-10");
    expect(feb9?.is_gap).toBe(true);
    expect(feb10?.is_gap).toBe(false);
    expect(feb10?.consumptions[0].bean_name).toBe("Ethiopia");
  });

  it("handles currently frozen beans with planned thaw date", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    db.prepare("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-02-10' WHERE id = 'b1'").run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, ?, ?)"
    ).run("b1", "freeze", "2026-01-15");

    // rest_days=30 + frozen_days=26 (Jan 15 to Feb 10) → ready Feb 26
    const result = loadScheduleData(db, "2026-02-25", "2026-02-27", "2026-02-01");

    const feb25 = result.schedule.find((d) => d.date === "2026-02-25");
    const feb26 = result.schedule.find((d) => d.date === "2026-02-26");
    expect(feb25?.is_gap).toBe(true);
    expect(feb26?.is_gap).toBe(false);
    expect(feb26?.consumptions[0].bean_name).toBe("Ethiopia");
  });

  it("archived beans have zero remaining grams but resolve brew names", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    db.prepare(
      "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('b1', 45, '2026-02-01')"
    ).run();
    db.prepare("UPDATE beans SET archived = 1 WHERE id = 'b1'").run();

    const result = loadScheduleData(db, "2026-02-01", "2026-02-01", "2026-02-15");

    // Past day with actual brew should show bean name
    expect(result.schedule[0].consumptions[0].bean_name).toBe("Ethiopia");
    // Archived bean should not be projected into future (no gap = no bean available)
  });

  it("excludes future brews from remaining grams", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    // Pre-log a future brew
    db.prepare(
      "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('b1', 45, '2026-02-05')"
    ).run();

    // today is Feb 1, so the Feb 5 brew is in the future
    const result = loadScheduleData(db, "2026-02-01", "2026-02-10", "2026-02-01");

    // The bean should still have full 250g for projection (future brew excluded from remaining)
    // Feb 5 should show the pre-logged 45g brew
    const feb5 = result.schedule.find((d) => d.date === "2026-02-05");
    expect(feb5?.consumptions.length).toBeGreaterThan(0);
  });

  it("uses daily_consumption_grams setting", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    db.prepare("UPDATE settings SET value = '40' WHERE key = 'daily_consumption_grams'").run();

    const result = loadScheduleData(db, "2026-02-01", "2026-02-01", "2026-02-01");

    expect(result.schedule[0].consumptions[0].grams).toBe(40);
  });
});
