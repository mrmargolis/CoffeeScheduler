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
