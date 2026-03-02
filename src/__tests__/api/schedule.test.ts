import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";
import { computeSchedule, SchedulerBean } from "@/lib/scheduler";
import { autoThawBeans } from "@/lib/auto-thaw";
import { loadScheduleData } from "@/lib/schedule-loader";

describe("schedule API integration", () => {
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

  it("produces schedule from database beans", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);

    const { schedule } = loadScheduleData(db, "2026-01-31", "2026-02-04", "2026-01-01");

    expect(schedule).toHaveLength(5);
    expect(schedule[0].consumptions[0].bean_name).toBe("Ethiopia");
    // 250g / 45g per day = 5.55 days → runs out during day 6
    const totalConsumed = schedule.reduce(
      (sum, day) =>
        sum + day.consumptions.reduce((s, c) => s + c.grams, 0),
      0
    );
    expect(totalConsumed).toBe(225); // 5 days * 45g
  });

  it("uses roaster defaults for rest days", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-15", 250);
    db.prepare(
      "INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Square Mile', 14)"
    ).run();

    const rows = db
      .prepare(
        `SELECT
          b.*,
          COALESCE(b.rest_days, rd.rest_days, CAST((SELECT value FROM settings WHERE key = 'default_rest_days') AS INTEGER)) as effective_rest_days,
          COALESCE((SELECT SUM(br.ground_coffee_grams) FROM brews br WHERE br.bean_id = b.id), 0) as total_brewed_grams
        FROM beans b
        LEFT JOIN roaster_defaults rd ON rd.roaster = b.roaster
        WHERE b.archived = 0`
      )
      .all() as any[];

    expect(rows[0].effective_rest_days).toBe(14);
  });

  it("computes frozen days from freeze events", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-10')"
    ).run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'thaw', '2026-01-20')"
    ).run();

    // loadScheduleData computes frozen_days internally; verify via schedule behavior.
    // Bean roasted Jan 1 with default 30 rest days + 10 frozen days = ready Feb 10.
    const { schedule } = loadScheduleData(db, "2026-02-09", "2026-02-11", "2026-02-01");

    expect(schedule[0].is_gap).toBe(true); // Feb 9: not ready
    expect(schedule[1].is_gap).toBe(false); // Feb 10: ready
    expect(schedule[1].consumptions[0].bean_name).toBe("Ethiopia");
  });

  it("loads skip days from DB and passes to scheduler correctly", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);

    db.prepare(
      "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)"
    ).run("2026-02-01", "2026-02-02", "Travel");

    const { schedule } = loadScheduleData(db, "2026-01-31", "2026-02-04", "2026-01-01");

    // Feb 1 and Feb 2 should be skip days
    const feb1 = schedule.find((d) => d.date === "2026-02-01");
    const feb2 = schedule.find((d) => d.date === "2026-02-02");
    expect(feb1?.is_skip).toBe(true);
    expect(feb2?.is_skip).toBe(true);
    expect(feb1?.consumptions).toHaveLength(0);
  });

  it("frozen bean with planned thaw date appears in schedule with correct ready date", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    db.prepare("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-02-10' WHERE id = 'b1'").run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-15')"
    ).run();

    // Ready date = Jan 1 + 30 (rest) + 26 (frozen from Jan 15 to Feb 10) = Feb 26
    const { schedule } = loadScheduleData(db, "2026-02-25", "2026-02-27", "2026-02-01");

    expect(schedule[0].is_gap).toBe(true); // Feb 25: not ready
    expect(schedule[1].is_gap).toBe(false); // Feb 26: ready
    expect(schedule[1].consumptions[0].bean_name).toBe("Ethiopia");
  });

  it("archived bean brews show correct name (not Unknown)", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    db.prepare(
      "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('b1', 45, '2026-02-01')"
    ).run();
    db.prepare("UPDATE beans SET archived = 1 WHERE id = 'b1'").run();

    const { schedule } = loadScheduleData(db, "2026-02-01", "2026-02-01", "2026-02-15");

    // Past day with actual brew should show bean name, not "Unknown"
    expect(schedule[0].consumptions[0].bean_name).toBe("Ethiopia");
  });

  it("auto-thaw fires when planned_thaw_date <= today", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    db.prepare("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-02-01' WHERE id = 'b1'").run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-15')"
    ).run();

    // Auto-thaw with today = Feb 1 (planned thaw date)
    autoThawBeans(db, "2026-02-01");

    const bean = db.prepare("SELECT is_frozen, planned_thaw_date FROM beans WHERE id = 'b1'").get() as any;
    expect(bean.is_frozen).toBe(0);
    expect(bean.planned_thaw_date).toBeNull();

    // Check thaw event was inserted
    const events = db.prepare(
      "SELECT event_type, event_date FROM freeze_events WHERE bean_id = 'b1' ORDER BY id"
    ).all() as any[];
    expect(events).toHaveLength(2);
    expect(events[1].event_type).toBe("thaw");
    expect(events[1].event_date).toBe("2026-02-01");
  });
});
