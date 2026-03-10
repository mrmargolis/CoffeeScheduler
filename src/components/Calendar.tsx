"use client";

import { useMemo, useState } from "react";
import ScheduleInfoPopover from "./ScheduleInfoPopover";
import DayOptionsModal from "./DayOptionsModal";
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";
import useSWR, { mutate } from "swr";
import { ScheduleDay, SkipDayRange, ConsumptionOverride } from "@/lib/types";
import { buildCalendarEvents } from "@/lib/calendar-utils";
import { today as getToday, localDateStr } from "@/lib/date-utils";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

interface CalendarProps {
  onSelectBean?: (beanId: string) => void;
}

export default function Calendar({ onSelectBean }: CalendarProps) {
  const today = getToday();
  const [selectedDate, setSelectedDate] = useState<string | null>(null);

  // Fetch 2 months back and 4 months forward
  const startDate = (() => {
    const d = new Date();
    d.setMonth(d.getMonth() - 2);
    d.setDate(1);
    return localDateStr(d);
  })();
  const endDate = (() => {
    const d = new Date();
    d.setMonth(d.getMonth() + 4);
    return localDateStr(d);
  })();

  const { data: schedule } = useSWR<ScheduleDay[]>(
    `/api/schedule?start=${startDate}&end=${endDate}`,
    fetcher
  );

  const { data: skipDayRanges, mutate: mutateSkipDays } = useSWR<SkipDayRange[]>(
    "/api/skip-days",
    fetcher
  );

  const { data: consumptionOverrides, mutate: mutateOverrides } = useSWR<ConsumptionOverride[]>(
    "/api/consumption-overrides",
    fetcher
  );

  const { events, summary } = useMemo(
    () => buildCalendarEvents(schedule || null, skipDayRanges, today, consumptionOverrides),
    [schedule, skipDayRanges, today, consumptionOverrides]
  );

  // Check if selected date is a skip day
  const isSkipDay = useMemo(() => {
    if (!selectedDate || !skipDayRanges) return false;
    return skipDayRanges.some(
      (r) => selectedDate >= r.start_date && selectedDate <= r.end_date
    );
  }, [selectedDate, skipDayRanges]);

  // Find existing override for selected date
  const existingOverride = useMemo(() => {
    if (!selectedDate || !consumptionOverrides) return null;
    return consumptionOverrides.find(
      (o) => selectedDate >= o.start_date && selectedDate <= o.end_date
    ) || null;
  }, [selectedDate, consumptionOverrides]);

  const revalidateSchedule = () => {
    mutate(
      (key: string) => key?.startsWith("/api/schedule"),
      undefined,
      { revalidate: true }
    );
  };

  const handleToggleSkip = async (date: string) => {
    await fetch("/api/skip-days/toggle", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ date }),
    });
    mutateSkipDays();
    revalidateSchedule();
  };

  const handleSaveOverride = async (override: {
    start_date: string;
    end_date: string;
    daily_grams: number;
    dose_size_grams: number;
  }) => {
    await fetch("/api/consumption-overrides", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(override),
    });
    mutateOverrides();
    revalidateSchedule();
  };

  const handleClearOverride = async (id: number) => {
    await fetch(`/api/consumption-overrides/${id}`, {
      method: "DELETE",
    });
    mutateOverrides();
    revalidateSchedule();
  };

  return (
    <div>
      {/* Summary Banner */}
      {summary && (
        <div className="mb-4 flex items-center gap-4 text-sm">
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
          <ScheduleInfoPopover />
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
          dateClick={(info) => {
            setSelectedDate(info.dateStr);
          }}
          eventClick={(info) => {
            const beanId = info.event.extendedProps?.beanId;
            if (beanId && onSelectBean) {
              onSelectBean(beanId);
            }
          }}
          eventDidMount={(info) => {
            if (info.event.classNames.includes("skip-day") || info.event.classNames.includes("gap-day")) {
              info.el.title = info.event.title;
            }
          }}
          eventDisplay="block"
          dayMaxEvents={4}
        />
      </div>

      {selectedDate && (
        <DayOptionsModal
          date={selectedDate}
          isSkipDay={isSkipDay}
          existingOverride={existingOverride}
          onClose={() => setSelectedDate(null)}
          onToggleSkip={handleToggleSkip}
          onSaveOverride={handleSaveOverride}
          onClearOverride={handleClearOverride}
        />
      )}
    </div>
  );
}
