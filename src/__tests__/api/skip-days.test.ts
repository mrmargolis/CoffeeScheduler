import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";
import { computeSchedule, SchedulerBean } from "@/lib/scheduler";
import { dateRange } from "@/lib/date-utils";

describe("skip-days CRUD", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
    initializeSchema(db);
  });

  function insertSkipRange(start: string, end: string, reason?: string) {
    return db
      .prepare(
        "INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)"
      )
      .run(start, end, reason || null);
  }

  function getSkipRanges() {
    return db
      .prepare("SELECT * FROM skip_days ORDER BY start_date")
      .all() as any[];
  }

  function getSkipDaysSet(scheduleStart: string, scheduleEnd: string): Set<string> {
    const ranges = db
      .prepare(
        `SELECT start_date, end_date FROM skip_days
         WHERE start_date <= ? AND end_date >= ?`
      )
      .all(scheduleEnd, scheduleStart) as { start_date: string; end_date: string }[];

    const skipDays = new Set<string>();
    for (const range of ranges) {
      const rangeStart = range.start_date < scheduleStart ? scheduleStart : range.start_date;
      const rangeEnd = range.end_date > scheduleEnd ? scheduleEnd : range.end_date;
      for (const date of dateRange(rangeStart, rangeEnd)) {
        skipDays.add(date);
      }
    }
    return skipDays;
  }

  function makeSchedulerBean(overrides: Partial<SchedulerBean> = {}): SchedulerBean {
    return {
      id: "bean-1",
      name: "Test Bean",
      roaster: "Test Roaster",
      roast_date: "2026-01-01",
      weight_grams: 250,
      remaining_grams: 250,
      effective_rest_days: 30,
      is_frozen: false,
      display_order: null,
      frozen_days: 0,
      ...overrides,
    };
  }

  it("CRUD lifecycle: create, read, update, delete", () => {
    // Create
    const result = insertSkipRange("2026-03-01", "2026-03-05", "Vacation");
    expect(result.lastInsertRowid).toBeDefined();

    // Read
    let ranges = getSkipRanges();
    expect(ranges).toHaveLength(1);
    expect(ranges[0].start_date).toBe("2026-03-01");
    expect(ranges[0].end_date).toBe("2026-03-05");
    expect(ranges[0].reason).toBe("Vacation");

    const id = ranges[0].id;

    // Update
    db.prepare(
      "UPDATE skip_days SET end_date = ?, reason = ? WHERE id = ?"
    ).run("2026-03-03", "Short trip", id);

    ranges = getSkipRanges();
    expect(ranges[0].end_date).toBe("2026-03-03");
    expect(ranges[0].reason).toBe("Short trip");

    // Delete
    db.prepare("DELETE FROM skip_days WHERE id = ?").run(id);
    ranges = getSkipRanges();
    expect(ranges).toHaveLength(0);
  });

  it("delete removes skip days from schedule", () => {
    const bean = makeSchedulerBean({ remaining_grams: 250 });

    // Add skip range
    insertSkipRange("2026-02-01", "2026-02-02");

    // Verify schedule has skips
    let skipDays = getSkipDaysSet("2026-01-31", "2026-02-04");
    let schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-04",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
      skipDays,
    });

    expect(schedule.find((d) => d.date === "2026-02-01")?.is_skip).toBe(true);
    expect(schedule.find((d) => d.date === "2026-02-02")?.is_skip).toBe(true);

    // Delete the range
    const ranges = getSkipRanges();
    db.prepare("DELETE FROM skip_days WHERE id = ?").run(ranges[0].id);

    // Verify schedule no longer has skips
    skipDays = getSkipDaysSet("2026-01-31", "2026-02-04");
    schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-04",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
      skipDays,
    });

    expect(schedule.find((d) => d.date === "2026-02-01")?.is_skip).toBe(false);
    expect(schedule.find((d) => d.date === "2026-02-02")?.is_skip).toBe(false);
  });

  it("update dates: shorten a vacation", () => {
    const bean = makeSchedulerBean({ remaining_grams: 250 });

    insertSkipRange("2026-02-01", "2026-02-05", "Vacation");
    const ranges = getSkipRanges();

    // Shorten to Feb 1-3
    db.prepare("UPDATE skip_days SET end_date = ? WHERE id = ?").run(
      "2026-02-03",
      ranges[0].id
    );

    const skipDays = getSkipDaysSet("2026-01-31", "2026-02-07");
    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-07",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
      skipDays,
    });

    // Feb 1-3: skip
    expect(schedule.find((d) => d.date === "2026-02-01")?.is_skip).toBe(true);
    expect(schedule.find((d) => d.date === "2026-02-03")?.is_skip).toBe(true);
    // Feb 4-5: not skip (freed days)
    expect(schedule.find((d) => d.date === "2026-02-04")?.is_skip).toBe(false);
    expect(schedule.find((d) => d.date === "2026-02-05")?.is_skip).toBe(false);
  });

  // --- Toggle logic tests ---

  function addDays(iso: string, n: number): string {
    const d = new Date(iso + "T00:00:00Z");
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().split("T")[0];
  }

  /** Mimics the toggle endpoint logic directly against the DB. */
  function toggleSkipDay(date: string): boolean {
    const containingRange = db
      .prepare("SELECT * FROM skip_days WHERE start_date <= ? AND end_date >= ?")
      .get(date, date) as any | undefined;

    if (containingRange) {
      const { id, start_date, end_date, reason } = containingRange;
      if (start_date === date && end_date === date) {
        db.prepare("DELETE FROM skip_days WHERE id = ?").run(id);
      } else if (start_date === date) {
        db.prepare("UPDATE skip_days SET start_date = ? WHERE id = ?").run(addDays(date, 1), id);
      } else if (end_date === date) {
        db.prepare("UPDATE skip_days SET end_date = ? WHERE id = ?").run(addDays(date, -1), id);
      } else {
        const beforeEnd = addDays(date, -1);
        const afterStart = addDays(date, 1);
        db.prepare("DELETE FROM skip_days WHERE id = ?").run(id);
        db.prepare("INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)").run(start_date, beforeEnd, reason);
        db.prepare("INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)").run(afterStart, end_date, reason);
      }
      return false; // toggled off
    }

    const prevDay = addDays(date, -1);
    const nextDay = addDays(date, 1);
    const prevRange = db.prepare("SELECT * FROM skip_days WHERE end_date = ?").get(prevDay) as any | undefined;
    const nextRange = db.prepare("SELECT * FROM skip_days WHERE start_date = ?").get(nextDay) as any | undefined;

    if (prevRange && nextRange) {
      db.prepare("UPDATE skip_days SET end_date = ? WHERE id = ?").run(nextRange.end_date, prevRange.id);
      db.prepare("DELETE FROM skip_days WHERE id = ?").run(nextRange.id);
    } else if (prevRange) {
      db.prepare("UPDATE skip_days SET end_date = ? WHERE id = ?").run(date, prevRange.id);
    } else if (nextRange) {
      db.prepare("UPDATE skip_days SET start_date = ? WHERE id = ?").run(date, nextRange.id);
    } else {
      db.prepare("INSERT INTO skip_days (start_date, end_date, reason) VALUES (?, ?, ?)").run(date, date, null);
    }
    return true; // toggled on
  }

  it("toggle on: insert a single-day skip", () => {
    const result = toggleSkipDay("2026-03-10");
    expect(result).toBe(true);
    const ranges = getSkipRanges();
    expect(ranges).toHaveLength(1);
    expect(ranges[0].start_date).toBe("2026-03-10");
    expect(ranges[0].end_date).toBe("2026-03-10");
  });

  it("toggle off: remove a single-day skip", () => {
    insertSkipRange("2026-03-10", "2026-03-10");
    const result = toggleSkipDay("2026-03-10");
    expect(result).toBe(false);
    expect(getSkipRanges()).toHaveLength(0);
  });

  it("toggle off start of range: shrinks from start", () => {
    insertSkipRange("2026-03-10", "2026-03-15", "Trip");
    const result = toggleSkipDay("2026-03-10");
    expect(result).toBe(false);
    const ranges = getSkipRanges();
    expect(ranges).toHaveLength(1);
    expect(ranges[0].start_date).toBe("2026-03-11");
    expect(ranges[0].end_date).toBe("2026-03-15");
  });

  it("toggle off end of range: shrinks from end", () => {
    insertSkipRange("2026-03-10", "2026-03-15");
    const result = toggleSkipDay("2026-03-15");
    expect(result).toBe(false);
    const ranges = getSkipRanges();
    expect(ranges).toHaveLength(1);
    expect(ranges[0].start_date).toBe("2026-03-10");
    expect(ranges[0].end_date).toBe("2026-03-14");
  });

  it("toggle off middle of range: splits into two", () => {
    insertSkipRange("2026-03-10", "2026-03-15", "Vacation");
    const result = toggleSkipDay("2026-03-12");
    expect(result).toBe(false);
    const ranges = getSkipRanges();
    expect(ranges).toHaveLength(2);
    expect(ranges[0].start_date).toBe("2026-03-10");
    expect(ranges[0].end_date).toBe("2026-03-11");
    expect(ranges[0].reason).toBe("Vacation");
    expect(ranges[1].start_date).toBe("2026-03-13");
    expect(ranges[1].end_date).toBe("2026-03-15");
    expect(ranges[1].reason).toBe("Vacation");
  });

  it("toggle on adjacent to previous range: merges", () => {
    insertSkipRange("2026-03-10", "2026-03-12");
    const result = toggleSkipDay("2026-03-13");
    expect(result).toBe(true);
    const ranges = getSkipRanges();
    expect(ranges).toHaveLength(1);
    expect(ranges[0].start_date).toBe("2026-03-10");
    expect(ranges[0].end_date).toBe("2026-03-13");
  });

  it("toggle on adjacent to next range: merges", () => {
    insertSkipRange("2026-03-12", "2026-03-15");
    const result = toggleSkipDay("2026-03-11");
    expect(result).toBe(true);
    const ranges = getSkipRanges();
    expect(ranges).toHaveLength(1);
    expect(ranges[0].start_date).toBe("2026-03-11");
    expect(ranges[0].end_date).toBe("2026-03-15");
  });

  it("toggle on between two adjacent ranges: merges all three", () => {
    insertSkipRange("2026-03-10", "2026-03-12");
    insertSkipRange("2026-03-14", "2026-03-16");
    const result = toggleSkipDay("2026-03-13");
    expect(result).toBe(true);
    const ranges = getSkipRanges();
    expect(ranges).toHaveLength(1);
    expect(ranges[0].start_date).toBe("2026-03-10");
    expect(ranges[0].end_date).toBe("2026-03-16");
  });

  it("update dates: extend a vacation", () => {
    const bean = makeSchedulerBean({ remaining_grams: 250 });

    insertSkipRange("2026-02-01", "2026-02-03");
    const ranges = getSkipRanges();

    // Extend to Feb 1-6
    db.prepare("UPDATE skip_days SET end_date = ? WHERE id = ?").run(
      "2026-02-06",
      ranges[0].id
    );

    const skipDays = getSkipDaysSet("2026-01-31", "2026-02-08");
    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-08",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
      skipDays,
    });

    // Feb 1-6: all skip
    for (let day = 1; day <= 6; day++) {
      const dateStr = `2026-02-0${day}`;
      expect(schedule.find((d) => d.date === dateStr)?.is_skip).toBe(true);
    }
    // Feb 7: not skip, consumption shifts here
    expect(schedule.find((d) => d.date === "2026-02-07")?.is_skip).toBe(false);
    expect(
      schedule.find((d) => d.date === "2026-02-07")?.consumptions.length
    ).toBeGreaterThan(0);
  });
});
