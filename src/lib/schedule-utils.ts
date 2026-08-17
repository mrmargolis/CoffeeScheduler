import { ScheduleDay } from "./types";

/**
 * Scan a schedule and return the last date each bean appears in consumptions.
 * This is the projected finish date for each bean.
 */
export function extractBeanFinishDates(
  schedule: ScheduleDay[]
): Map<string, string> {
  const finishDates = new Map<string, string>();
  for (const day of schedule) {
    for (const c of day.consumptions) {
      finishDates.set(c.bean_id, day.date);
    }
  }
  return finishDates;
}

/**
 * Scan a schedule and return the first date each bean appears in consumptions.
 * This is the projected start date for each bean.
 */
export function extractBeanStartDates(
  schedule: ScheduleDay[]
): Map<string, string> {
  const startDates = new Map<string, string>();
  for (const day of schedule) {
    for (const c of day.consumptions) {
      if (!startDates.has(c.bean_id)) {
        startDates.set(c.bean_id, day.date);
      }
    }
  }
  return startDates;
}

/**
 * Scan a schedule and return, for each bean started before its ready date, how
 * many days early its first scheduled day is. Beans that start on or after
 * their ready date are omitted.
 */
export function extractBeanEarlyStarts(
  schedule: ScheduleDay[]
): Map<string, number> {
  const earlyStarts = new Map<string, number>();
  const seen = new Set<string>();
  for (const day of schedule) {
    for (const c of day.consumptions) {
      if (seen.has(c.bean_id)) continue;
      seen.add(c.bean_id);
      if (c.days_early && c.days_early > 0) {
        earlyStarts.set(c.bean_id, c.days_early);
      }
    }
  }
  return earlyStarts;
}
