"use client";

import { useState, useCallback, useMemo, useRef, useEffect } from "react";
import useSWR, { mutate } from "swr";
import { BeanWithComputed, ScheduleDay } from "@/lib/types";
import { today as getToday, scheduleKey, formatShortDay } from "@/lib/date-utils";
import { effectiveAge } from "@/lib/freeze-utils";
import {
  extractBeanEarlyStarts,
  extractBeanFinishDates,
  extractBeanStartDates,
} from "@/lib/schedule-utils";
import { daysBetween } from "@/lib/date-utils";
import { useRoasterColors } from "@/lib/use-roaster-colors";
import { ChevronRight, GripIcon, SnowflakeIcon, WarningIcon } from "./icons";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

// Persists across mount/unmount cycles so scroll position survives BeanDetail view
let persistedScrollTop = 0;

interface Status {
  label: string;
  className: string;
  dot?: boolean;
}

function status(bean: BeanWithComputed, isInProgress: boolean): Status {
  if (isInProgress)
    return { label: "Brewing", className: "bg-ok-wash text-ok", dot: true };
  if (bean.remaining_grams <= 0)
    return { label: "Finished", className: "bg-raised text-ink-faint" };
  if (bean.is_frozen) {
    return {
      label: bean.planned_thaw_date
        ? `Thaw ${formatShortDay(bean.planned_thaw_date)}`
        : "No thaw date",
      className: "bg-cold-wash text-cold",
    };
  }
  if (!bean.ready_date)
    return { label: "No roast date", className: "bg-early-wash text-early" };
  if (bean.ready_date > getToday())
    return {
      label: `Rests until ${formatShortDay(bean.ready_date)}`,
      className: "bg-rest-wash text-rest",
    };
  return { label: "Ready", className: "bg-ok-wash text-ok" };
}

export default function BeanList({
  onSelectBean,
  selectedBeanId,
}: {
  onSelectBean: (id: string) => void;
  selectedBeanId: string | null;
}) {
  const { data: beans, error } = useSWR<BeanWithComputed[]>(
    "/api/beans",
    fetcher
  );
  const colorFor = useRoasterColors();

  const { data: schedule } = useSWR<ScheduleDay[]>(scheduleKey(), fetcher);

  // Compute effective age-at-finish for each bean (frozen days subtracted)
  const ageAtFinish = useMemo(() => {
    const map = new Map<string, number>();
    if (!schedule || !beans) return map;
    const finishDates = extractBeanFinishDates(schedule);
    for (const bean of beans) {
      const finishDate = finishDates.get(bean.id);
      if (!finishDate) continue;
      const age = effectiveAge(bean.roast_date, finishDate, bean.frozen_days);
      if (age !== null) map.set(bean.id, age);
    }
    return map;
  }, [schedule, beans]);

  // Compute effective age-at-start for each bean (frozen days subtracted)
  const ageAtStart = useMemo(() => {
    const map = new Map<string, number>();
    if (!schedule || !beans) return map;
    const startDates = extractBeanStartDates(schedule);
    for (const bean of beans) {
      const startDate = startDates.get(bean.id);
      if (!startDate) continue;
      const age = effectiveAge(bean.roast_date, startDate, bean.frozen_days);
      if (age !== null) map.set(bean.id, age);
    }
    return map;
  }, [schedule, beans]);

  // Bags whose queue position starts them before they've finished resting
  const earlyStarts = useMemo(
    () => (schedule ? extractBeanEarlyStarts(schedule) : new Map<string, number>()),
    [schedule]
  );

  const startDates = useMemo(
    () => (schedule ? extractBeanStartDates(schedule) : new Map<string, string>()),
    [schedule]
  );

  const freezeSuggestions = useMemo(() => {
    const suggestions = new Map<string, string>();
    if (!beans || !schedule) return suggestions;

    const todayStr = getToday();

    // Criterion 1: Staleness risk
    // Bean is rested (ready_date <= today), not frozen, remaining > 0, and ageAtFinish > 60
    for (const bean of beans) {
      if (bean.is_frozen || bean.remaining_grams <= 0) continue;
      if (!bean.ready_date || bean.ready_date > todayStr) continue;
      const age = ageAtFinish.get(bean.id);
      if (age && age > 60) {
        suggestions.set(bean.id, "Will go stale — consider freezing");
      }
    }

    // Criterion 2: Low frozen stock
    const frozenCount = beans.filter((b) => b.is_frozen).length;
    const finishDates = extractBeanFinishDates(schedule);
    let lastScheduledDate = todayStr;
    for (const d of finishDates.values()) {
      if (d > lastScheduledDate) lastScheduledDate = d;
    }
    const scheduleExtendsDays = daysBetween(todayStr, lastScheduledDate);

    if (frozenCount <= 2 && scheduleExtendsDays > 30) {
      const restedBeans = beans.filter(
        (b) =>
          !b.is_frozen &&
          b.remaining_grams > 0 &&
          b.ready_date &&
          b.ready_date <= todayStr &&
          !suggestions.has(b.id)
      );
      const lastRested = restedBeans[restedBeans.length - 1];
      if (lastRested) {
        suggestions.set(
          lastRested.id,
          "Low frozen stock — consider freezing"
        );
      }
    }

    return suggestions;
  }, [beans, schedule, ageAtFinish]);

  const activeBeans = useMemo(
    () => (beans ? beans.filter((b) => !b.is_frozen && b.remaining_grams > 0) : []),
    [beans]
  );
  const frozenBeans = useMemo(
    () => (beans ? beans.filter((b) => b.is_frozen) : []),
    [beans]
  );
  const finishedBeans = useMemo(
    () =>
      beans ? beans.filter((b) => !b.is_frozen && b.remaining_grams <= 0) : [],
    [beans]
  );

  const [collapsedSections, setCollapsedSections] = useState<
    Record<string, boolean>
  >({ active: false, frozen: true, finished: true });

  const toggleSection = useCallback((key: string) => {
    setCollapsedSections((prev) => {
      // Active and Frozen are mutually exclusive: expanding one collapses the other
      if (key === "frozen" && prev.frozen) {
        return { ...prev, frozen: false, active: true };
      }
      if (key === "active" && prev.active) {
        return { ...prev, active: false, frozen: true };
      }
      return { ...prev, [key]: !prev[key] };
    });
  }, []);

  const scrollRef = useRef<HTMLDivElement>(null);

  // Restore scroll position when component mounts (e.g. returning from BeanDetail)
  useEffect(() => {
    if (scrollRef.current && persistedScrollTop > 0) {
      scrollRef.current.scrollTop = persistedScrollTop;
    }
  }, []);

  const handleSelectBean = useCallback(
    (id: string) => {
      if (scrollRef.current) {
        persistedScrollTop = scrollRef.current.scrollTop;
      }
      onSelectBean(id);
    },
    [onSelectBean]
  );

  const [dragOverId, setDragOverId] = useState<string | null>(null);
  const [dragId, setDragId] = useState<string | null>(null);

  const handleDragStart = useCallback((e: React.DragEvent, beanId: string) => {
    setDragId(beanId);
    e.dataTransfer.effectAllowed = "move";
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent, beanId: string) => {
    e.preventDefault();
    setDragOverId(beanId);
  }, []);

  const handleDrop = useCallback(
    async (e: React.DragEvent, targetId: string) => {
      e.preventDefault();
      setDragOverId(null);
      if (!dragId || !beans || dragId === targetId) return;

      const dragIndex = beans.findIndex((b) => b.id === dragId);
      const targetIndex = beans.findIndex((b) => b.id === targetId);
      if (dragIndex === -1 || targetIndex === -1) return;

      // Reorder locally
      const reordered = [...beans];
      const [moved] = reordered.splice(dragIndex, 1);
      reordered.splice(targetIndex, 0, moved);

      // Save new order to server
      const updates = reordered.map((b, i) => ({
        id: b.id,
        display_order: i + 1,
      }));

      // Optimistic update
      mutate(
        "/api/beans",
        reordered.map((b, i) => ({ ...b, display_order: i + 1 })),
        false
      );

      // Persist each order
      await Promise.all(
        updates.map((u) =>
          fetch(`/api/beans/${u.id}`, {
            method: "PATCH",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ display_order: u.display_order }),
          })
        )
      );

      mutate("/api/beans");
      mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
        revalidate: true,
      });
      setDragId(null);
    },
    [dragId, beans]
  );

  // The first active bean with remaining < weight is "in progress" (currently being consumed)
  const inProgressBeanId = useMemo(() => {
    const bean = activeBeans.find((b) => b.remaining_grams < b.weight_grams);
    return bean?.id ?? null;
  }, [activeBeans]);

  if (error)
    return <div className="p-4 text-[13px] text-alert">Failed to load beans</div>;
  if (!beans)
    return <div className="p-4 text-[13px] text-ink-faint">Loading…</div>;

  if (beans.length === 0) {
    return (
      <div className="px-4 py-10 text-center">
        <p className="text-[13.5px] text-ink-muted">No bags yet.</p>
        <p className="mt-1.5 text-[12.5px] text-ink-faint">
          Import a BeanConqueror export to get started.
        </p>
      </div>
    );
  }

  const renderBean = (bean: BeanWithComputed, draggable: boolean) => {
    const roasterColor = colorFor(bean.roaster);
    const isInProgress = bean.id === inProgressBeanId;
    const isSelected = selectedBeanId === bean.id;
    const pill = status(bean, isInProgress);
    const early = earlyStarts.get(bean.id);
    const finishAge = ageAtFinish.get(bean.id) ?? 0;
    const startAge = ageAtStart.get(bean.id);
    const suggestion = freezeSuggestions.get(bean.id);
    const consumed = bean.weight_grams - bean.remaining_grams;
    const showProgress = bean.weight_grams > 0 && consumed > 0 && bean.remaining_grams > 0;

    return (
      <div
        key={bean.id}
        {...(draggable
          ? {
              draggable: true,
              onDragStart: (e: React.DragEvent) => handleDragStart(e, bean.id),
              onDragOver: (e: React.DragEvent) => handleDragOver(e, bean.id),
              onDrop: (e: React.DragEvent) => handleDrop(e, bean.id),
              onDragEnd: () => {
                setDragOverId(null);
                setDragId(null);
              },
            }
          : {})}
        onClick={() => handleSelectBean(bean.id)}
        className={`flex gap-2.5 border-b border-l-[3px] border-b-rule py-3.5 pr-4 transition-colors ${
          draggable ? "cursor-grab pl-[13px] active:cursor-grabbing" : "cursor-pointer pl-[27px]"
        } ${
          isSelected
            ? "border-l-accent bg-accent-wash/60"
            : isInProgress
              ? "border-l-accent bg-[#1f1b17]"
              : "border-l-transparent hover:bg-raised"
        } ${dragOverId === bean.id ? "border-t-2 border-t-accent" : ""}`}
      >
        {draggable && (
          <div className="flex shrink-0 flex-col items-center gap-1.5 pt-0.5 text-ink-faint">
            <GripIcon />
            {bean.display_order != null && (
              <span className="font-mono text-[10.5px] tabular-nums">
                {bean.display_order}
              </span>
            )}
          </div>
        )}

        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <div className="flex items-start gap-2.5">
            <div className="min-w-0 flex-1">
              <p className="truncate text-[13.5px] font-semibold tracking-[-0.005em]">
                {bean.name}
              </p>
              <div className="mt-[3px] flex items-center gap-1.5">
                <span
                  className="h-1.5 w-1.5 shrink-0 rounded-full"
                  style={{ backgroundColor: roasterColor.border }}
                />
                <span className="truncate text-[12px] text-ink-muted">
                  {bean.roaster}
                </span>
              </div>
            </div>
            <span
              className={`inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-medium ${pill.className}`}
            >
              {pill.dot && (
                <span className="h-[5px] w-[5px] rounded-full bg-current" />
              )}
              {pill.label}
            </span>
          </div>

          {showProgress && (
            <div className="flex items-center gap-2.5">
              <div className="h-1 flex-1 overflow-hidden rounded-full bg-track">
                <div
                  className="h-full rounded-full bg-accent"
                  style={{
                    width: `${Math.min(100, (consumed / bean.weight_grams) * 100)}%`,
                  }}
                />
              </div>
              <span className="shrink-0 font-mono text-[11.5px] tabular-nums text-ink-muted">
                {Math.round(bean.remaining_grams)} / {bean.weight_grams} g
              </span>
            </div>
          )}

          <div className="flex flex-wrap gap-x-3.5 gap-y-1 font-mono text-[11.5px] tabular-nums text-ink-faint">
            {!showProgress && (
              <span>{Math.round(bean.remaining_grams)} g</span>
            )}
            {startAge != null && <span>day {startAge} at the first cup</span>}
            {finishAge > 60 && (
              <span className="text-alert">day {finishAge} at the last</span>
            )}
            {bean.freeze_after_grams != null && !bean.is_frozen && (
              <span className="text-cold">freeze at {bean.freeze_after_grams} g</span>
            )}
          </div>

          {early != null && (
            <Callout tone="early">
              Starts {startDates.get(bean.id) ? formatShortDay(startDates.get(bean.id)!) : "soon"},{" "}
              {early} {early === 1 ? "day" : "days"} before it is rested.
            </Callout>
          )}

          {suggestion && <Callout tone="cold">{suggestion}</Callout>}
        </div>
      </div>
    );
  };

  const renderSectionHeader = (
    label: string,
    count: number,
    sectionKey: string,
    icon?: React.ReactNode
  ) => {
    const collapsed = collapsedSections[sectionKey];
    return (
      <button
        key={`header-${label}`}
        onClick={() => toggleSection(sectionKey)}
        className="flex w-full select-none items-center gap-2 border-b border-rule bg-raised px-4 py-2.5 text-left transition-colors hover:bg-elevated"
      >
        <ChevronRight
          size={12}
          className={`shrink-0 text-ink-faint transition-transform ${collapsed ? "" : "rotate-90"}`}
        />
        {icon}
        <span className="text-[10.5px] uppercase tracking-[0.09em] text-ink-faint">
          {label}
        </span>
        <span className="ml-auto font-mono text-[11px] tabular-nums text-ink-faint">
          {count}
        </span>
      </button>
    );
  };

  const section = (key: string, children: React.ReactNode) => (
    <div
      className="grid transition-[grid-template-rows] duration-200 ease-in-out"
      style={{ gridTemplateRows: collapsedSections[key] ? "0fr" : "1fr" }}
    >
      <div className="overflow-hidden">{children}</div>
    </div>
  );

  const stockedGrams = [...activeBeans, ...frozenBeans].reduce(
    (sum, b) => sum + Math.max(0, b.remaining_grams),
    0
  );

  return (
    <div
      ref={scrollRef}
      className="overflow-y-auto lg:max-h-[calc(100vh-13rem)]"
    >
      <div className="sticky top-0 z-10 flex items-center justify-between gap-3 border-b border-rule bg-panel px-4 py-3.5">
        <div className="flex items-baseline gap-2">
          <h2 className="text-[15px] font-semibold tracking-[-0.01em]">
            Backlog
          </h2>
          <span className="font-mono text-[12px] tabular-nums text-ink-faint">
            {activeBeans.length + frozenBeans.length} bags ·{" "}
            {stockedGrams >= 1000
              ? `${(stockedGrams / 1000).toFixed(1)} kg`
              : `${Math.round(stockedGrams)} g`}
          </span>
        </div>
        <span className="hidden text-[11.5px] text-ink-faint lg:block">
          Drag to reorder
        </span>
      </div>

      {renderSectionHeader("In the queue", activeBeans.length, "active")}
      {section(
        "active",
        activeBeans.length === 0 ? (
          <p className="px-4 py-5 text-center text-[12.5px] text-ink-faint">
            Nothing in the queue — thaw a bag or import more.
          </p>
        ) : (
          activeBeans.map((bean) => renderBean(bean, true))
        )
      )}

      {renderSectionHeader(
        "Freezer",
        frozenBeans.length,
        "frozen",
        <SnowflakeIcon size={12} className="shrink-0 text-cold" />
      )}
      {section("frozen", frozenBeans.map((bean) => renderBean(bean, false)))}

      {finishedBeans.length > 0 && (
        <>
          {renderSectionHeader("Finished", finishedBeans.length, "finished")}
          {section(
            "finished",
            finishedBeans.map((bean) => renderBean(bean, false))
          )}
        </>
      )}
    </div>
  );
}

function Callout({
  tone,
  children,
}: {
  tone: "early" | "cold";
  children: React.ReactNode;
}) {
  const toneClass =
    tone === "early" ? "bg-early-wash text-early" : "bg-cold-wash text-cold";
  return (
    <div className={`flex items-start gap-2 rounded-md px-2.5 py-2 ${toneClass}`}>
      {tone === "early" ? (
        <WarningIcon size={13} className="mt-px shrink-0" />
      ) : (
        <SnowflakeIcon size={13} className="mt-px shrink-0" />
      )}
      <span className="text-[11.5px] leading-[1.45] text-pretty">{children}</span>
    </div>
  );
}
