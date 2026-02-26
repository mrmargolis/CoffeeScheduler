"use client";

import { useMemo } from "react";
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";
import useSWR, { mutate } from "swr";
import { ScheduleDay, SkipDayRange } from "@/lib/types";
import { buildCalendarEvents } from "@/lib/calendar-utils";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

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

  const { events, summary } = useMemo(
    () => buildCalendarEvents(schedule || null, skipDayRanges, today),
    [schedule, skipDayRanges, today]
  );

  return (
    <div>
      {/* Summary Banner */}
      {summary && (
        <div className="mb-4 flex gap-4 text-sm">
          <div className="bg-green-950 border border-green-800 rounded-lg px-4 py-2">
            <span className="text-green-300 font-medium">
              {summary.daysOfCoffee} days
            </span>
            <span className="text-green-400"> of coffee remaining</span>
          </div>
          {summary.nextGapDate && (
            <div className="bg-red-950 border border-red-800 rounded-lg px-4 py-2">
              <span className="text-red-300 font-medium">Gap:</span>
              <span className="text-red-400"> {summary.nextGapDate}</span>
            </div>
          )}
        </div>
      )}

      <div className="bg-gray-900 rounded-xl shadow-sm border border-gray-700 p-4">
        <FullCalendar
          plugins={[dayGridPlugin, interactionPlugin]}
          initialView="dayGridMonth"
          events={events}
          headerToolbar={{
            left: "prev,next today",
            center: "title",
            right: "",
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
