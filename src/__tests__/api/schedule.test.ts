import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";
import { computeSchedule, SchedulerBean } from "@/lib/scheduler";
import { daysBetween, dateRange } from "@/lib/date-utils";
import { autoThawBeans } from "@/lib/auto-thaw";

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

  function getSchedulerBeans(): SchedulerBean[] {
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

    return rows.map((row: any) => ({
      id: row.id,
      name: row.name,
      roaster: row.roaster,
      roast_date: row.roast_date,
      weight_grams: row.weight_grams,
      remaining_grams:
        row.weight_grams - row.total_brewed_grams,
      effective_rest_days: row.effective_rest_days,
      is_frozen: Boolean(row.is_frozen),
      planned_thaw_date: row.planned_thaw_date || null,
      display_order: row.display_order,
      frozen_days: 0,
    }));
  }

  it("produces schedule from database beans", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);

    const beans = getSchedulerBeans();
    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-04",
      dailyConsumptionGrams: 45,
      beans,
      actualBrews: [],
      today: "2026-01-01",
    });

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

    const beans = getSchedulerBeans();
    expect(beans[0].effective_rest_days).toBe(14);
  });

  it("computes frozen days from freeze events", () => {
    // Simulating what the API route does
    const freezeEvents = [
      { bean_id: "b1", event_type: "freeze", event_date: "2026-01-10" },
      { bean_id: "b1", event_type: "thaw", event_date: "2026-01-20" },
    ];

    let frozenDays = 0;
    let freezeStart: string | null = null;
    for (const event of freezeEvents) {
      if (event.event_type === "freeze") {
        freezeStart = event.event_date;
      } else if (event.event_type === "thaw" && freezeStart) {
        frozenDays += daysBetween(freezeStart, event.event_date);
        freezeStart = null;
      }
    }

    expect(frozenDays).toBe(10);
  });

  it("loads skip days from DB and passes to scheduler correctly", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);

    // Insert skip day range
    db.prepare(
      "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)"
    ).run("2026-02-01", "2026-02-02", "Travel");

    // Query skip days the same way the API route does
    const startDate = "2026-01-31";
    const endDate = "2026-02-04";
    const skipDayRanges = db
      .prepare(
        `SELECT start_date, end_date FROM skip_days
         WHERE start_date <= ? AND end_date >= ?`
      )
      .all(endDate, startDate) as { start_date: string; end_date: string }[];

    const skipDays = new Set<string>();
    for (const range of skipDayRanges) {
      const rangeStart = range.start_date < startDate ? startDate : range.start_date;
      const rangeEnd = range.end_date > endDate ? endDate : range.end_date;
      for (const date of dateRange(rangeStart, rangeEnd)) {
        skipDays.add(date);
      }
    }

    expect(skipDays.has("2026-02-01")).toBe(true);
    expect(skipDays.has("2026-02-02")).toBe(true);
    expect(skipDays.size).toBe(2);

    const beans = getSchedulerBeans();
    const schedule = computeSchedule({
      startDate,
      endDate,
      dailyConsumptionGrams: 45,
      beans,
      actualBrews: [],
      today: "2026-01-01",
      skipDays,
    });

    // Feb 1 and Feb 2 should be skip days
    const feb1 = schedule.find((d) => d.date === "2026-02-01");
    const feb2 = schedule.find((d) => d.date === "2026-02-02");
    expect(feb1?.is_skip).toBe(true);
    expect(feb2?.is_skip).toBe(true);
    expect(feb1?.consumptions).toHaveLength(0);
  });

  it("frozen bean with planned thaw date appears in schedule with correct ready date", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    // Freeze the bean and set planned thaw date
    db.prepare("UPDATE beans SET is_frozen = 1, planned_thaw_date = '2026-02-10' WHERE id = 'b1'").run();
    db.prepare(
      "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES ('b1', 'freeze', '2026-01-15')"
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

    // Compute frozen days using planned_thaw_date as end
    const freezeStart = "2026-01-15";
    const plannedThaw = "2026-02-10";
    const frozenDays = daysBetween(freezeStart, plannedThaw); // 26 days

    const schedulerBeans: SchedulerBean[] = rows.map((row: any) => ({
      id: row.id,
      name: row.name,
      roaster: row.roaster,
      roast_date: row.roast_date,
      weight_grams: row.weight_grams,
      remaining_grams: row.weight_grams - row.total_brewed_grams,
      effective_rest_days: row.effective_rest_days,
      is_frozen: Boolean(row.is_frozen),
      planned_thaw_date: row.planned_thaw_date || null,
      display_order: row.display_order,
      frozen_days: frozenDays,
    }));

    // Ready date = Jan 1 + 30 (rest) + 26 (frozen) = Feb 26
    const schedule = computeSchedule({
      startDate: "2026-02-25",
      endDate: "2026-02-27",
      dailyConsumptionGrams: 45,
      beans: schedulerBeans,
      actualBrews: [],
      today: "2026-02-01",
    });

    expect(schedule[0].is_gap).toBe(true); // Feb 25: not ready
    expect(schedule[1].is_gap).toBe(false); // Feb 26: ready
    expect(schedule[1].consumptions[0].bean_name).toBe("Ethiopia");
  });

  it("archived bean brews show correct name (not Unknown)", () => {
    insertBean("b1", "Ethiopia", "Square Mile", "2026-01-01", 250);
    // Brew some coffee, then archive the bean
    db.prepare(
      "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('b1', 45, '2026-02-01')"
    ).run();
    db.prepare("UPDATE beans SET archived = 1 WHERE id = 'b1'").run();

    // Fetch all beans (including archived) as the schedule route now does
    const rows = db
      .prepare(
        `SELECT
          b.*,
          COALESCE(b.rest_days, rd.rest_days, CAST((SELECT value FROM settings WHERE key = 'default_rest_days') AS INTEGER)) as effective_rest_days,
          COALESCE((SELECT SUM(br.ground_coffee_grams) FROM brews br WHERE br.bean_id = b.id), 0) as total_brewed_grams
        FROM beans b
        LEFT JOIN roaster_defaults rd ON rd.roaster = b.roaster`
      )
      .all() as any[];

    const schedulerBeans: SchedulerBean[] = rows.map((row: any) => ({
      id: row.id,
      name: row.name,
      roaster: row.roaster,
      roast_date: row.roast_date,
      weight_grams: row.weight_grams,
      remaining_grams: row.archived ? 0 : row.weight_grams - row.total_brewed_grams,
      effective_rest_days: row.effective_rest_days,
      is_frozen: Boolean(row.is_frozen),
      planned_thaw_date: row.planned_thaw_date || null,
      display_order: row.display_order,
      frozen_days: 0,
    }));

    const schedule = computeSchedule({
      startDate: "2026-02-01",
      endDate: "2026-02-01",
      dailyConsumptionGrams: 45,
      beans: schedulerBeans,
      actualBrews: [
        { bean_id: "b1", creation_date: "2026-02-01", ground_coffee_grams: 45 },
      ],
      today: "2026-02-15",
    });

    // Past day with actual brew should show bean name, not "Unknown"
    expect(schedule[0].consumptions[0].bean_name).toBe("Ethiopia");
    // Archived bean should not be projected (remaining_grams = 0)
    expect(schedulerBeans[0].remaining_grams).toBe(0);
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
