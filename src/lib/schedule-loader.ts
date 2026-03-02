import type Database from "better-sqlite3";
import { computeSchedule, SchedulerBean } from "./scheduler";
import { daysBetween, dateRange } from "./date-utils";
import { queryBeanRowsRaw } from "./bean-queries";
import { ScheduleDay, SkipDayRange } from "./types";

export interface ScheduleData {
  schedule: ScheduleDay[];
  skipDayRanges: SkipDayRange[];
}

export function loadScheduleData(
  db: Database.Database,
  startDate: string,
  endDate: string,
  today: string
): ScheduleData {
  // Get settings
  const settingsRows = db
    .prepare("SELECT key, value FROM settings")
    .all() as { key: string; value: string }[];
  const settings = Object.fromEntries(settingsRows.map((r) => [r.key, r.value]));
  const dailyConsumptionGrams =
    Number(settings.daily_consumption_grams) || 45;

  // Get all beans (including archived) so past brews can resolve names.
  const beanRows = queryBeanRowsRaw(db);

  // Compute frozen days for each bean from freeze_events
  const freezeEvents = db
    .prepare(
      "SELECT bean_id, event_type, event_date FROM freeze_events ORDER BY event_date"
    )
    .all() as { bean_id: string; event_type: string; event_date: string }[];

  const frozenDaysMap = new Map<string, number>();
  const activeFreezeStart = new Map<string, string>();

  for (const event of freezeEvents) {
    if (event.event_type === "freeze") {
      activeFreezeStart.set(event.bean_id, event.event_date);
    } else if (event.event_type === "thaw") {
      const freezeStart = activeFreezeStart.get(event.bean_id);
      if (freezeStart) {
        const days = daysBetween(freezeStart, event.event_date);
        frozenDaysMap.set(
          event.bean_id,
          (frozenDaysMap.get(event.bean_id) || 0) + days
        );
        activeFreezeStart.delete(event.bean_id);
      }
    }
  }

  // For currently frozen beans, add days from last freeze to today (or planned thaw date)
  const beanPlannedThaw = new Map<string, string | null>();
  for (const row of beanRows) {
    beanPlannedThaw.set(row.id, row.planned_thaw_date || null);
  }
  for (const [beanId, freezeStart] of activeFreezeStart) {
    const plannedThaw = beanPlannedThaw.get(beanId);
    const freezeEnd = plannedThaw || today;
    const days = daysBetween(freezeStart, freezeEnd);
    frozenDaysMap.set(
      beanId,
      (frozenDaysMap.get(beanId) || 0) + days
    );
  }

  const schedulerBeans: SchedulerBean[] = beanRows.map((row) => {
    const isArchived = Boolean(row.archived);
    return {
      id: row.id,
      name: row.name,
      roaster: row.roaster,
      roast_date: row.roast_date,
      weight_grams: row.weight_grams,
      remaining_grams: isArchived
        ? 0
        : row.weight_grams - row.total_brewed_grams,
      effective_rest_days: row.effective_rest_days,
      is_frozen: Boolean(row.is_frozen),
      planned_thaw_date: row.planned_thaw_date || null,
      freeze_after_grams: row.freeze_after_grams ?? null,
      display_order: row.display_order,
      frozen_days: frozenDaysMap.get(row.id) || 0,
    };
  });

  // Exclude future brews from remaining_grams
  const futureBrewTotals = db
    .prepare(
      `SELECT bean_id, SUM(ground_coffee_grams) as total_grams
       FROM brews WHERE creation_date > ?
       GROUP BY bean_id`
    )
    .all(today) as { bean_id: string; total_grams: number }[];

  for (const fb of futureBrewTotals) {
    const bean = schedulerBeans.find((b) => b.id === fb.bean_id);
    if (bean) bean.remaining_grams += fb.total_grams;
  }

  // Get actual brews in range
  const actualBrews = db
    .prepare(
      `SELECT bean_id, creation_date, ground_coffee_grams
       FROM brews
       WHERE creation_date >= ? AND creation_date <= ?
       ORDER BY creation_date`
    )
    .all(startDate, endDate) as {
    bean_id: string;
    creation_date: string;
    ground_coffee_grams: number;
  }[];

  // Get skip day ranges overlapping the schedule range
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

  const schedule = computeSchedule({
    startDate,
    endDate,
    dailyConsumptionGrams,
    beans: schedulerBeans,
    actualBrews,
    today,
    skipDays,
  });

  return { schedule, skipDayRanges };
}
