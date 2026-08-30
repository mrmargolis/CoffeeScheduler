"use client";

import { useMemo } from "react";
import useSWR from "swr";
import { BeanWithComputed, ScheduleDay } from "@/lib/types";
import { summarizeSchedule } from "@/lib/calendar-utils";
import { getRoasterColor } from "@/lib/colors";
import { extractBeanEarlyStarts, extractBeanStartDates } from "@/lib/schedule-utils";
import { today as getToday, scheduleKey, formatShortDay } from "@/lib/date-utils";
import ScheduleInfoPopover from "./ScheduleInfoPopover";
import { WarningIcon } from "./icons";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

/**
 * The one-line answer to "am I fine?": how long the coffee lasts, what is on
 * the grinder, and the single thing most worth looking at.
 */
export default function RunwayStrip({
  onSelectBean,
}: {
  onSelectBean?: (beanId: string) => void;
}) {
  const today = getToday();
  const { data: schedule } = useSWR<ScheduleDay[]>(scheduleKey(), fetcher);
  const { data: beans } = useSWR<BeanWithComputed[]>("/api/beans", fetcher);

  const summary = useMemo(
    () => (schedule ? summarizeSchedule(schedule, today) : null),
    [schedule, today]
  );

  const brewing = useMemo(() => {
    if (!beans) return null;
    return (
      beans.find(
        (b) =>
          !b.is_frozen &&
          b.remaining_grams > 0 &&
          b.remaining_grams < b.weight_grams
      ) ?? null
    );
  }, [beans]);

  // What needs a look: a dry stretch outranks a bag started before it rested.
  const attention = useMemo(() => {
    if (summary?.nextGapDate) {
      return {
        tone: "alert" as const,
        text: "No coffee scheduled from",
        date: formatShortDay(summary.nextGapDate),
        beanId: null,
      };
    }
    if (!schedule || !beans) return null;

    const earlyStarts = extractBeanEarlyStarts(schedule);
    const startDates = extractBeanStartDates(schedule);
    let worst: { beanId: string; days: number } | null = null;
    for (const [beanId, days] of earlyStarts) {
      if (!worst || days > worst.days) worst = { beanId, days };
    }
    if (!worst) return null;

    const bean = beans.find((b) => b.id === worst!.beanId);
    if (!bean) return null;
    const startDate = startDates.get(bean.id);
    return {
      tone: "early" as const,
      text: `${bean.name} starts ${worst.days} ${worst.days === 1 ? "day" : "days"} before it is rested`,
      date: startDate ? formatShortDay(startDate) : null,
      beanId: bean.id,
    };
  }, [summary, schedule, beans]);

  if (!summary) return null;

  return (
    <div className="flex flex-col gap-3.5 rounded-xl border border-rule bg-panel px-4 py-3.5 lg:flex-row lg:items-stretch lg:gap-7 lg:px-[22px] lg:py-4">
      {/* Runway */}
      <div className="flex flex-col gap-0.5 lg:border-r lg:border-rule lg:pr-7">
        <span className="hidden text-[10.5px] uppercase tracking-[0.09em] text-ink-faint lg:block">
          Runway
        </span>
        <div className="flex items-baseline gap-1.5">
          <span className="font-mono text-[26px] font-medium leading-none tabular-nums lg:text-[30px]">
            {summary.daysOfCoffee}
          </span>
          <span className="text-[13px] text-ink-muted">days of coffee</span>
        </div>
      </div>

      {/* On the grinder */}
      {brewing && (
        <div className="flex min-w-0 flex-col gap-0.5 lg:border-r lg:border-rule lg:pr-7">
          <span className="hidden text-[10.5px] uppercase tracking-[0.09em] text-ink-faint lg:block">
            On the grinder
          </span>
          <button
            onClick={() => onSelectBean?.(brewing.id)}
            className="mt-0.5 flex min-w-0 items-center gap-2 text-left"
          >
            <span
              className="h-[15px] w-[3px] shrink-0 rounded-sm"
              style={{ backgroundColor: getRoasterColor(brewing.roaster).border }}
            />
            <span className="truncate text-[13.5px] font-medium">
              {brewing.name}
            </span>
            <span className="shrink-0 font-mono text-[12px] tabular-nums text-ink-faint">
              {Math.round(brewing.remaining_grams)} g left
            </span>
          </button>
        </div>
      )}

      {/* Needs a look */}
      {attention && (
        <div className="flex min-w-0 flex-col gap-0.5">
          <span className="hidden text-[10.5px] uppercase tracking-[0.09em] text-ink-faint lg:block">
            Needs a look
          </span>
          <button
            onClick={() => attention.beanId && onSelectBean?.(attention.beanId)}
            className={`mt-0.5 flex min-w-0 items-center gap-2 text-left ${
              attention.tone === "alert" ? "text-alert" : "text-early"
            }`}
          >
            <WarningIcon size={14} className="shrink-0" />
            <span className="truncate text-[13px] lg:text-[13.5px]">
              {attention.text}
            </span>
            {attention.date && (
              <span className="shrink-0 font-mono text-[12px] tabular-nums text-ink-faint">
                {attention.date}
              </span>
            )}
          </button>
        </div>
      )}

      <div className="hidden flex-1 lg:block" />
      <div className="hidden items-center lg:flex">
        <ScheduleInfoPopover />
      </div>
    </div>
  );
}
