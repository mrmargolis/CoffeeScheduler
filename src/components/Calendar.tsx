"use client";

import { useMemo, useRef, useState } from "react";
import DayOptionsModal from "./DayOptionsModal";
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import interactionPlugin from "@fullcalendar/interaction";
import useSWR, { mutate } from "swr";
import { ScheduleDay, SkipDayRange, ConsumptionOverride } from "@/lib/types";
import { buildCalendarEvents } from "@/lib/calendar-utils";
import { today as getToday, scheduleKey } from "@/lib/date-utils";
import { useRoasterColors } from "@/lib/use-roaster-colors";
import { ChevronLeft, ChevronRight } from "./icons";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

interface CalendarProps {
  onSelectBean?: (beanId: string) => void;
}

const toolbarButton =
  "flex h-8 items-center justify-center border border-rule-strong text-ink-muted transition-colors hover:bg-elevated hover:text-ink";

export default function Calendar({ onSelectBean }: CalendarProps) {
  const today = getToday();
  const colorFor = useRoasterColors();
  const calendarRef = useRef<FullCalendar>(null);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [monthLabel, setMonthLabel] = useState<{ month: string; year: string }>({
    month: "",
    year: "",
  });
  const [viewRange, setViewRange] = useState<{ start: string; end: string } | null>(
    null
  );

  const { data: schedule } = useSWR<ScheduleDay[]>(scheduleKey(), fetcher);

  const { data: skipDayRanges, mutate: mutateSkipDays } = useSWR<SkipDayRange[]>(
    "/api/skip-days",
    fetcher
  );

  const { data: consumptionOverrides, mutate: mutateOverrides } = useSWR<
    ConsumptionOverride[]
  >("/api/consumption-overrides", fetcher);

  const { events } = useMemo(
    () =>
      buildCalendarEvents(
        schedule || null,
        skipDayRanges,
        today,
        consumptionOverrides,
        colorFor
      ),
    [schedule, skipDayRanges, today, consumptionOverrides, colorFor]
  );

  // On narrow screens the bars lose their labels, so name the bags on show.
  const bagsInView = useMemo(() => {
    if (!viewRange) return [];
    const seen = new Map<string, { name: string; rail: string }>();
    for (const event of events) {
      const props = event.extendedProps;
      if (props?.kind !== "bean" || !props.beanId) continue;
      const end = event.end ?? event.start;
      if (end <= viewRange.start || event.start >= viewRange.end) continue;
      if (!seen.has(props.beanId)) {
        seen.set(props.beanId, {
          name: event.title,
          rail: props.rail ?? event.borderColor,
        });
      }
    }
    return [...seen.entries()].map(([id, bag]) => ({ id, ...bag }));
  }, [events, viewRange]);

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
    return (
      consumptionOverrides.find(
        (o) => selectedDate >= o.start_date && selectedDate <= o.end_date
      ) || null
    );
  }, [selectedDate, consumptionOverrides]);

  const revalidateSchedule = () => {
    mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
      revalidate: true,
    });
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
    await fetch(`/api/consumption-overrides/${id}`, { method: "DELETE" });
    mutateOverrides();
    revalidateSchedule();
  };

  const api = () => calendarRef.current?.getApi();

  return (
    <div className="overflow-hidden rounded-xl border border-rule bg-panel">
      {/* Toolbar */}
      <div className="flex items-center justify-between px-4 py-3 lg:px-[18px] lg:pb-[13px] lg:pt-[14px]">
        <div className="flex items-baseline gap-[7px] lg:gap-[9px]">
          <h2 className="text-[17px] font-semibold tracking-[-0.015em] lg:text-[19px]">
            {monthLabel.month}
          </h2>
          <span className="font-mono text-[13px] text-ink-faint lg:text-[15px]">
            {monthLabel.year}
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          <button
            onClick={() => api()?.prev()}
            aria-label="Previous month"
            className={`${toolbarButton} w-11 rounded-l-lg border-r-0 lg:w-8`}
          >
            <ChevronLeft size={15} />
          </button>
          <button
            onClick={() => api()?.next()}
            aria-label="Next month"
            className={`${toolbarButton} -ml-1.5 w-11 rounded-r-lg lg:w-8`}
          >
            <ChevronRight size={15} />
          </button>
          <button
            onClick={() => api()?.today()}
            className={`${toolbarButton} ml-1 rounded-lg px-3 text-[12.5px]`}
          >
            Today
          </button>
        </div>
      </div>

      <FullCalendar
        ref={calendarRef}
        plugins={[dayGridPlugin, interactionPlugin]}
        initialView="dayGridMonth"
        events={events}
        headerToolbar={false}
        height="auto"
        datesSet={(arg) => {
          const start = arg.view.currentStart;
          setMonthLabel({
            month: start.toLocaleDateString(undefined, { month: "long" }),
            year: String(start.getFullYear()),
          });
          setViewRange({
            start: arg.startStr.slice(0, 10),
            end: arg.endStr.slice(0, 10),
          });
        }}
        dateClick={(info) => setSelectedDate(info.dateStr)}
        eventClick={(info) => {
          const beanId = info.event.extendedProps?.beanId;
          if (beanId && onSelectBean) onSelectBean(beanId);
        }}
        eventContent={(arg) => {
          const props = arg.event.extendedProps as {
            meta?: string;
            daysEarly?: number;
          };
          return (
            <div className="fc-bar">
              <span className="fc-bar-name">{arg.event.title}</span>
              {props.daysEarly ? (
                <span className="fc-bar-flag">{props.daysEarly} d early</span>
              ) : null}
              {props.meta ? (
                <span className="fc-bar-meta">{props.meta}</span>
              ) : null}
            </div>
          );
        }}
        eventDidMount={(info) => {
          const rail = info.event.extendedProps?.rail;
          if (rail) info.el.style.setProperty("--rail", rail);
          // The labels are hidden on narrow screens, so keep them reachable.
          const props = info.event.extendedProps as { meta?: string };
          info.el.title = props.meta
            ? `${info.event.title} — ${props.meta}`
            : info.event.title;
        }}
        eventDisplay="block"
        dayMaxEvents={4}
      />

      {/* Which bag is which, for the label-less stripes on phones */}
      {bagsInView.length > 0 && (
        <div className="flex flex-wrap gap-x-4 gap-y-2 border-t border-rule bg-raised px-4 py-3 lg:hidden">
          {bagsInView.map((bag) => (
            <button
              key={bag.id}
              onClick={() => onSelectBean?.(bag.id)}
              className="flex min-w-0 items-center gap-2"
            >
              <span
                className="h-2.5 w-[3px] shrink-0 rounded-sm"
                style={{ backgroundColor: bag.rail }}
              />
              <span className="truncate text-[12px] text-ink-muted">
                {bag.name}
              </span>
            </button>
          ))}
        </div>
      )}

      {/* Legend */}
      <div className="hidden flex-wrap items-center gap-5 border-t border-rule bg-raised px-[18px] py-3 lg:flex">
        <LegendKey tint="#2d2114" rail="#e1b581" label="Projected" />
        <LegendKey tint="#172632" rail="#8fc4f1" label="Brewed" dim />
        <LegendKey label="Skip day" dashed />
        <LegendKey tint="#2d2114" rail="#f3a677" label="Started before rested" dashed />
        <LegendKey tint="#2f1b18" rail="#ea8e82" label="Gap — nothing available" />
        <span className="ml-auto text-[11.5px] text-ink-faint">
          Click a day to skip it or change the dose
        </span>
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

function LegendKey({
  tint,
  rail,
  label,
  dashed,
  dim,
}: {
  tint?: string;
  rail?: string;
  label: string;
  dashed?: boolean;
  dim?: boolean;
}) {
  return (
    <div className="flex items-center gap-[7px]">
      <span
        className="h-2 w-4 rounded-sm border-l-4 box-border"
        style={{
          backgroundColor: tint ?? "transparent",
          borderLeftColor: rail ?? "#3d3833",
          borderLeftStyle: dashed ? "dashed" : "solid",
          borderWidth: tint ? undefined : 1,
          borderStyle: tint ? undefined : "dashed",
          borderColor: tint ? undefined : "#3d3833",
          opacity: dim ? 0.72 : 1,
        }}
      />
      <span className="text-[11.5px] text-ink-faint">{label}</span>
    </div>
  );
}
