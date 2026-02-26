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
