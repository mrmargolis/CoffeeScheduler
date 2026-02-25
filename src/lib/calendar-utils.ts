import { ScheduleDay, SkipDayRange } from "./types";
import { getRoasterColor } from "./colors";

export interface CalendarEvent {
  title: string;
  start: string;
  end?: string;
  allDay: boolean;
  backgroundColor: string;
  borderColor: string;
  textColor: string;
  classNames?: string[];
  extendedProps?: { beanId: string };
}

export interface ScheduleSummary {
  daysOfCoffee: number;
  nextGapDate: string | null;
}

function nextDay(iso: string): string {
  const d = new Date(iso + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().split("T")[0];
}

export function buildCalendarEvents(
  schedule: ScheduleDay[] | null,
  skipDayRanges: SkipDayRange[] | undefined,
  today: string
): { events: CalendarEvent[]; summary: ScheduleSummary | null } {
  if (!schedule) return { events: [], summary: null };

  // Build a map from date to skip reason for display
  const skipReasonMap = new Map<string, string>();
  if (skipDayRanges) {
    for (const range of skipDayRanges) {
      let current = range.start_date;
      while (current <= range.end_date) {
        skipReasonMap.set(current, range.reason || "Skip");
        const d = new Date(current + "T00:00:00Z");
        d.setUTCDate(d.getUTCDate() + 1);
        current = d.toISOString().split("T")[0];
      }
    }
  }

  const events: CalendarEvent[] = [];

  // Group consecutive days per bean into spans
  const beanSpans = new Map<
    string,
    { start: string; end: string; name: string; roaster: string; totalGrams: number }
  >();

  for (const day of schedule) {
    // Skip day indicator
    if (day.is_skip) {
      const reason = skipReasonMap.get(day.date) || "Skip";
      events.push({
        title: reason,
        start: day.date,
        allDay: true,
        backgroundColor: "#451a03",
        borderColor: "#d97706",
        textColor: "#fbbf24",
        classNames: ["skip-day"],
      });

      // Break all bean spans across skip days
      for (const [key, span] of beanSpans) {
        const color = getRoasterColor(span.roaster);
        events.push({
          title: `${Math.round(span.totalGrams)}g · ${span.name}`,
          start: span.start,
          end: span.end,
          allDay: true,
          backgroundColor: color.bg,
          borderColor: color.border,
          textColor: color.text,
          extendedProps: { beanId: key },
        });
        beanSpans.delete(key);
      }
      continue;
    }

    // Gap day indicator
    if (day.is_gap && !day.is_actual) {
      events.push({
        title: "No coffee!",
        start: day.date,
        allDay: true,
        backgroundColor: "#450a0a",
        borderColor: "#ef4444",
        textColor: "#fca5a5",
        classNames: ["gap-day"],
      });
    }

    if (day.consumptions.length > 1) {
      // Multi-bean day: flush active spans and show individual single-day events
      for (const [key, span] of beanSpans) {
        const color = getRoasterColor(span.roaster);
        events.push({
          title: `${Math.round(span.totalGrams)}g · ${span.name}`,
          start: span.start,
          end: span.end,
          allDay: true,
          backgroundColor: color.bg,
          borderColor: color.border,
          textColor: color.text,
          extendedProps: { beanId: key },
        });
      }
      beanSpans.clear();

      for (const consumption of day.consumptions) {
        const color = getRoasterColor(consumption.roaster);
        events.push({
          title: `${Math.round(consumption.grams)}g · ${consumption.bean_name}`,
          start: day.date,
          end: nextDay(day.date),
          allDay: true,
          backgroundColor: color.bg,
          borderColor: color.border,
          textColor: color.text,
          extendedProps: { beanId: consumption.bean_id },
        });
      }
    } else {
      for (const consumption of day.consumptions) {
        const key = consumption.bean_id;
        const existing = beanSpans.get(key);

        if (existing && existing.end === day.date) {
          // Extend span - end is exclusive, so end === today means yesterday was the last day
          existing.end = nextDay(day.date);
          existing.totalGrams += consumption.grams;
        } else {
          // Flush existing span if any
          if (existing) {
            const color = getRoasterColor(existing.roaster);
            events.push({
              title: `${Math.round(existing.totalGrams)}g · ${existing.name}`,
              start: existing.start,
              end: existing.end,
              allDay: true,
              backgroundColor: color.bg,
              borderColor: color.border,
              textColor: color.text,
              extendedProps: { beanId: key },
            });
          }
          // Start new span
          beanSpans.set(key, {
            start: day.date,
            end: nextDay(day.date),
            name: consumption.bean_name,
            roaster: consumption.roaster,
            totalGrams: consumption.grams,
          });
        }
      }
    }
  }

  // Flush remaining spans
  for (const [key, span] of beanSpans) {
    const color = getRoasterColor(span.roaster);
    events.push({
      title: `${Math.round(span.totalGrams)}g · ${span.name}`,
      start: span.start,
      end: span.end,
      allDay: true,
      backgroundColor: color.bg,
      borderColor: color.border,
      textColor: color.text,
      extendedProps: { beanId: key },
    });
  }

  // Compute summary
  const futureDays = schedule.filter(
    (d) => d.date >= today && !d.is_actual
  );
  const daysWithCoffee = futureDays.filter((d) => !d.is_gap && !d.is_skip).length;
  const firstGap = futureDays.find((d) => d.is_gap);
  return {
    events,
    summary: {
      daysOfCoffee: daysWithCoffee,
      nextGapDate: firstGap?.date || null,
    },
  };
}
