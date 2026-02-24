"use client";

import { useMemo } from "react";
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";
import useSWR, { mutate } from "swr";
import { ScheduleDay, SkipDayRange } from "@/lib/types";
import { getRoasterColor } from "@/lib/colors";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

/** Add one day to an ISO date string, using UTC to avoid DST issues. */
function nextDay(iso: string): string {
  const d = new Date(iso + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().split("T")[0];
}

interface CalendarProps {
  onSelectBean?: (beanId: string) => void;
}

export default function Calendar({ onSelectBean }: CalendarProps) {
  const today = new Date().toISOString().split("T")[0];
  // Fetch 2 months back and 4 months forward
  const startDate = (() => {
    const d = new Date();
    d.setMonth(d.getMonth() - 2);
    d.setDate(1);
    return d.toISOString().split("T")[0];
  })();
  const endDate = (() => {
    const d = new Date();
    d.setMonth(d.getMonth() + 4);
    return d.toISOString().split("T")[0];
  })();

  const { data: schedule } = useSWR<ScheduleDay[]>(
    `/api/schedule?start=${startDate}&end=${endDate}`,
    fetcher
  );

  const { data: skipDayRanges, mutate: mutateSkipDays } = useSWR<SkipDayRange[]>(
    "/api/skip-days",
    fetcher
  );

  const { events, summary } = useMemo(() => {
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

    const events: any[] = [];

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
          backgroundColor: "#fef3c7",
          borderColor: "#f59e0b",
          textColor: "#b45309",
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
          backgroundColor: "#fee2e2",
          borderColor: "#ef4444",
          textColor: "#dc2626",
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
  }, [schedule, skipDayRanges, today]);

  return (
    <div>
      {/* Summary Banner */}
      {summary && (
        <div className="mb-4 flex gap-4 text-sm">
          <div className="bg-green-50 border border-green-200 rounded-lg px-4 py-2">
            <span className="text-green-800 font-medium">
              {summary.daysOfCoffee} days
            </span>
            <span className="text-green-600"> of coffee remaining</span>
          </div>
          {summary.nextGapDate && (
            <div className="bg-red-50 border border-red-200 rounded-lg px-4 py-2">
              <span className="text-red-800 font-medium">Gap:</span>
              <span className="text-red-600"> {summary.nextGapDate}</span>
            </div>
          )}
        </div>
      )}

      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
        <FullCalendar
          plugins={[dayGridPlugin, interactionPlugin]}
          initialView="dayGridMonth"
          events={events}
          headerToolbar={{
            left: "prev,next today",
            center: "title",
            right: "dayGridMonth",
          }}
          height="auto"
          dateClick={async (info) => {
            await fetch("/api/skip-days/toggle", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ date: info.dateStr }),
            });
            mutateSkipDays();
            mutate(
              (key: string) => key?.startsWith("/api/schedule"),
              undefined,
              { revalidate: true }
            );
          }}
          eventClick={(info) => {
            const beanId = info.event.extendedProps?.beanId;
            if (beanId && onSelectBean) {
              onSelectBean(beanId);
            }
          }}
          eventDisplay="block"
          dayMaxEvents={4}
        />
      </div>
    </div>
  );
}
