import { ConsumptionOverride, ScheduleDay, SkipDayRange } from "./types";
import { getRoasterColor, RoasterColor } from "./colors";

export type CalendarEventKind = "bean" | "skip" | "gap" | "override";

export interface CalendarEvent {
  title: string;
  start: string;
  end?: string;
  allDay: boolean;
  backgroundColor: string;
  borderColor: string;
  textColor: string;
  classNames?: string[];
  extendedProps?: {
    kind: CalendarEventKind;
    beanId?: string;
    /** Roaster hue, used to paint the stripe on narrow screens. */
    rail?: string;
    /** Right-aligned mono detail on the bar, e.g. "7 d · 315 g". */
    meta?: string;
    /** > 0 when the bag was scheduled before it finished resting. */
    daysEarly?: number;
  };
}

export interface ScheduleSummary {
  daysOfCoffee: number;
  nextGapDate: string | null;
}

/** A run of consecutive days on the same bag, at the same certainty. */
interface BeanSpan {
  start: string;
  end: string; // exclusive
  name: string;
  roaster: string;
  totalGrams: number;
  days: number;
  isActual: boolean;
  daysEarly: number;
}

const SKIP_COLORS = { bg: "#1f1c1a", border: "#3d3833", text: "#807b74" };
const GAP_COLORS = { bg: "#2f1b18", border: "#ea8e82", text: "#f0cdc7" };
const OVERRIDE_COLORS = { bg: "#162733", border: "#8ec2e6", text: "#cfe3f2" };

function nextDay(iso: string): string {
  const d = new Date(iso + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().split("T")[0];
}

/** How a roaster maps to a colour for this render. */
export type RoasterPalette = (roaster: string) => RoasterColor;

function spanEvent(
  beanId: string,
  span: BeanSpan,
  colorFor: RoasterPalette
): CalendarEvent {
  const color = colorFor(span.roaster);
  const classNames: string[] = [];
  if (span.isActual) classNames.push("brewed");
  if (span.daysEarly > 0) classNames.push("early-start");

  return {
    title: span.name,
    start: span.start,
    end: span.end,
    allDay: true,
    backgroundColor: color.bg,
    borderColor: color.border,
    textColor: color.text,
    classNames,
    extendedProps: {
      kind: "bean",
      beanId,
      rail: color.border,
      meta: `${span.days} d · ${Math.round(span.totalGrams)} g`,
      daysEarly: span.daysEarly,
    },
  };
}

export function buildCalendarEvents(
  schedule: ScheduleDay[] | null,
  skipDayRanges: SkipDayRange[] | undefined,
  today: string,
  consumptionOverrides?: ConsumptionOverride[],
  colorFor: RoasterPalette = getRoasterColor
): { events: CalendarEvent[]; summary: ScheduleSummary | null } {
  if (!schedule) return { events: [], summary: null };

  // Build a map from date to skip reason for display
  const skipReasonMap = new Map<string, string>();
  if (skipDayRanges) {
    for (const range of skipDayRanges) {
      let current = range.start_date;
      while (current <= range.end_date) {
        skipReasonMap.set(current, range.reason || "Skip");
        current = nextDay(current);
      }
    }
  }

  // Build a map from date to override info for display
  const overrideMap = new Map<string, number>();
  if (Array.isArray(consumptionOverrides)) {
    for (const override of consumptionOverrides) {
      let current = override.start_date;
      while (current <= override.end_date) {
        overrideMap.set(current, override.daily_grams);
        current = nextDay(current);
      }
    }
  }

  const events: CalendarEvent[] = [];

  // Group consecutive days per bean into spans
  const beanSpans = new Map<string, BeanSpan>();

  const flushAll = () => {
    for (const [beanId, span] of beanSpans) {
      events.push(spanEvent(beanId, span, colorFor));
    }
    beanSpans.clear();
  };

  for (const day of schedule) {
    // Skip day indicator
    if (day.is_skip) {
      events.push({
        title: skipReasonMap.get(day.date) || "Skip",
        start: day.date,
        allDay: true,
        backgroundColor: SKIP_COLORS.bg,
        borderColor: SKIP_COLORS.border,
        textColor: SKIP_COLORS.text,
        classNames: ["skip-day"],
        extendedProps: { kind: "skip" },
      });

      // Break all bean spans across skip days
      flushAll();
      continue;
    }

    // Override day indicator
    const overrideGrams = overrideMap.get(day.date);
    if (overrideGrams !== undefined) {
      events.push({
        title: `${overrideGrams} g/day`,
        start: day.date,
        allDay: true,
        backgroundColor: OVERRIDE_COLORS.bg,
        borderColor: OVERRIDE_COLORS.border,
        textColor: OVERRIDE_COLORS.text,
        classNames: ["override-day"],
        extendedProps: { kind: "override" },
      });
    }

    // Gap day indicator
    if (day.is_gap && !day.is_actual) {
      events.push({
        title: "No coffee",
        start: day.date,
        allDay: true,
        backgroundColor: GAP_COLORS.bg,
        borderColor: GAP_COLORS.border,
        textColor: GAP_COLORS.text,
        classNames: ["gap-day"],
        extendedProps: { kind: "gap" },
      });
    }

    if (day.consumptions.length > 1) {
      // Multi-bean day: flush active spans and show individual single-day events
      flushAll();

      for (const consumption of day.consumptions) {
        const color = colorFor(consumption.roaster);
        const daysEarly = consumption.days_early ?? 0;
        const classNames: string[] = [];
        if (day.is_actual) classNames.push("brewed");
        if (daysEarly > 0) classNames.push("early-start");

        events.push({
          title: consumption.bean_name,
          start: day.date,
          end: nextDay(day.date),
          allDay: true,
          backgroundColor: color.bg,
          borderColor: color.border,
          textColor: color.text,
          classNames,
          extendedProps: {
            kind: "bean",
            beanId: consumption.bean_id,
            rail: color.border,
            meta: `${Math.round(consumption.grams)} g`,
            daysEarly,
          },
        });
      }
    } else {
      for (const consumption of day.consumptions) {
        const key = consumption.bean_id;
        const existing = beanSpans.get(key);
        const daysEarly = consumption.days_early ?? 0;

        // A span runs while the bag, the certainty (brewed vs projected) and
        // the day-to-day continuity all hold.
        if (
          existing &&
          existing.end === day.date &&
          existing.isActual === day.is_actual
        ) {
          // Extend span - end is exclusive, so end === today means yesterday was the last day
          existing.end = nextDay(day.date);
          existing.totalGrams += consumption.grams;
          existing.days += 1;
          existing.daysEarly = Math.max(existing.daysEarly, daysEarly);
        } else {
          // Flush existing span if any
          if (existing) {
            events.push(spanEvent(key, existing, colorFor));
          }
          // Start new span
          beanSpans.set(key, {
            start: day.date,
            end: nextDay(day.date),
            name: consumption.bean_name,
            roaster: consumption.roaster,
            totalGrams: consumption.grams,
            days: 1,
            isActual: day.is_actual,
            daysEarly,
          });
        }
      }
    }
  }

  // Flush remaining spans
  flushAll();

  return { events, summary: summarizeSchedule(schedule, today) };
}

/** Days of coffee still projected, and when the first dry day lands. */
export function summarizeSchedule(
  schedule: ScheduleDay[],
  today: string
): ScheduleSummary {
  const futureDays = schedule.filter((d) => d.date >= today && !d.is_actual);
  const firstGap = futureDays.find((d) => d.is_gap);
  return {
    daysOfCoffee: futureDays.filter((d) => !d.is_gap && !d.is_skip).length,
    nextGapDate: firstGap?.date || null,
  };
}
