"use client";

import { useState, useCallback, useMemo, useRef, useEffect } from "react";
import useSWR, { mutate } from "swr";
import { BeanWithComputed, ScheduleDay } from "@/lib/types";
import { getRoasterColor } from "@/lib/colors";
import { daysBetween, today as getToday } from "@/lib/date-utils";
import { extractBeanFinishDates, extractBeanStartDates } from "@/lib/schedule-utils";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

// Persists across mount/unmount cycles so scroll position survives BeanDetail view
let persistedScrollTop = 0;

function statusColor(bean: BeanWithComputed): string {
  if (bean.remaining_grams <= 0) return "bg-gray-700 text-gray-400";
  if (bean.is_frozen) return "bg-blue-900/50 text-blue-300";
  if (!bean.ready_date) return "bg-yellow-900/50 text-yellow-300";
  const today = getToday();
  if (bean.ready_date > today) return "bg-orange-900/50 text-orange-300";
  return "bg-green-900/50 text-green-300";
}

function statusLabel(bean: BeanWithComputed): string {
  if (bean.remaining_grams <= 0) return "Depleted";
  if (bean.is_frozen) {
    if (bean.planned_thaw_date) return `Thaw ${bean.planned_thaw_date}`;
    return "Frozen";
  }
  if (!bean.ready_date) return "No roast date";
  const today = getToday();
  if (bean.ready_date > today) {
    const days = daysBetween(today, bean.ready_date);
    return days === 1 ? "Ready in 1 day" : `Ready in ${days} days`;
  }
  return "Ready";
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

  // Use the same date range as Calendar so SWR returns the cached result
  const scheduleKey = useMemo(() => {
    const start = (() => {
      const d = new Date();
      d.setMonth(d.getMonth() - 2);
      d.setDate(1);
      return d.toISOString().split("T")[0];
    })();
    const end = (() => {
      const d = new Date();
      d.setMonth(d.getMonth() + 4);
      return d.toISOString().split("T")[0];
    })();
    return `/api/schedule?start=${start}&end=${end}`;
  }, []);

  const { data: schedule } = useSWR<ScheduleDay[]>(scheduleKey, fetcher);

  // Compute age-at-finish for each bean
  const ageAtFinish = useMemo(() => {
    const map = new Map<string, number>();
    if (!schedule || !beans) return map;
    const finishDates = extractBeanFinishDates(schedule);
    for (const bean of beans) {
      if (!bean.roast_date) continue;
      const finishDate = finishDates.get(bean.id);
      if (!finishDate) continue;
      map.set(bean.id, daysBetween(bean.roast_date, finishDate));
    }
    return map;
  }, [schedule, beans]);

  // Compute age-at-start for each bean
  const ageAtStart = useMemo(() => {
    const map = new Map<string, number>();
    if (!schedule || !beans) return map;
    const startDates = extractBeanStartDates(schedule);
    for (const bean of beans) {
      if (!bean.roast_date) continue;
      const startDate = startDates.get(bean.id);
      if (!startDate) continue;
      map.set(bean.id, daysBetween(bean.roast_date, startDate));
    }
    return map;
  }, [schedule, beans]);

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
        suggestions.set(bean.id, "Will go stale \u2014 consider freezing");
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
          "Low frozen stock \u2014 consider freezing"
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

  const [collapsedSections, setCollapsedSections] = useState<Record<string, boolean>>({
    active: false,
    frozen: true,
  });

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

  const handleSelectBean = useCallback((id: string) => {
    if (scrollRef.current) {
      persistedScrollTop = scrollRef.current.scrollTop;
    }
    onSelectBean(id);
  }, [onSelectBean]);

  const [dragOverId, setDragOverId] = useState<string | null>(null);
  const [dragId, setDragId] = useState<string | null>(null);

  const handleDragStart = useCallback(
    (e: React.DragEvent, beanId: string) => {
      setDragId(beanId);
      e.dataTransfer.effectAllowed = "move";
    },
    []
  );

  const handleDragOver = useCallback(
    (e: React.DragEvent, beanId: string) => {
      e.preventDefault();
      setDragOverId(beanId);
    },
    []
  );

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
    return <div className="p-4 text-red-400">Failed to load beans</div>;
  if (!beans) return <div className="p-4 text-gray-400">Loading...</div>;

  if (beans.length === 0) {
    return (
      <div className="p-4 text-gray-400 text-center">
        <p className="mb-2">No beans imported yet.</p>
        <p className="text-sm">Use the Import button to get started.</p>
      </div>
    );
  }

  const renderBean = (bean: BeanWithComputed, draggable: boolean) => {
    const roasterColor = getRoasterColor(bean.roaster);
    const isInProgress = bean.id === inProgressBeanId;
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
        className={`w-full text-left p-3 hover:bg-gray-800 transition-colors ${
          draggable ? "cursor-grab active:cursor-grabbing" : "cursor-pointer"
        } ${
          selectedBeanId === bean.id
            ? "bg-amber-950 border-l-2 border-amber-500"
            : isInProgress
              ? "border-l-2 border-green-500"
              : ""
        } ${dragOverId === bean.id ? "bg-amber-950/50 border-t-2 border-amber-500" : ""}`}
      >
        <div className="flex justify-between items-start">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5">
              <p className="text-sm font-medium text-gray-300 truncate">{bean.name}</p>
              {bean.display_order != null && (
                <span className="text-xs font-mono shrink-0 px-1 py-0.5 rounded bg-amber-900/50 text-amber-400">#{bean.display_order}</span>
              )}
            </div>
            <p className="text-xs text-gray-400 truncate">
              <span
                className="inline-block w-2 h-2 rounded-full mr-1"
                style={{ backgroundColor: roasterColor.border }}
              />
              {bean.roaster}
            </p>
          </div>
          <span
            className={`ml-2 px-2 py-0.5 rounded-full text-xs font-medium shrink-0 ${isInProgress ? "bg-green-900/50 text-green-300" : statusColor(bean)}`}
          >
            {isInProgress ? "Brewing" : statusLabel(bean)}
          </span>
        </div>
        <div className="mt-1 flex gap-3 text-xs text-gray-400">
          <span>{Math.round(bean.remaining_grams)}g remaining</span>
          {bean.ready_date && <span>Ready {bean.ready_date}</span>}
          {ageAtStart.has(bean.id) && (
            <span>{ageAtStart.get(bean.id)} days old at start</span>
          )}
          {bean.freeze_after_grams != null && !bean.is_frozen && (
            <span className="text-blue-400/60">Freeze at {bean.freeze_after_grams}g</span>
          )}
        </div>
        {(ageAtFinish.get(bean.id) ?? 0) > 60 && (
          <p className="mt-0.5 text-xs font-medium text-red-400">
            Finishes day {ageAtFinish.get(bean.id)}
          </p>
        )}
        {bean.weight_grams > 0 && bean.remaining_grams < bean.weight_grams && (
          <div className="mt-1.5 h-1 bg-gray-700 rounded-full overflow-hidden">
            <div
              className="h-full bg-amber-600 rounded-full transition-all"
              style={{ width: `${Math.min(100, ((bean.weight_grams - bean.remaining_grams) / bean.weight_grams) * 100)}%` }}
            />
          </div>
        )}
        {freezeSuggestions.has(bean.id) && (
          <p className="mt-0.5 text-xs font-medium text-blue-400">
            {freezeSuggestions.get(bean.id)}
          </p>
        )}
      </div>
    );
  };

  const renderSectionHeader = (
    label: string,
    count: number,
    sectionKey?: string
  ) => {
    const collapsed = sectionKey ? collapsedSections[sectionKey] : false;
    return (
      <div
        key={`header-${label}`}
        onClick={sectionKey ? () => toggleSection(sectionKey) : undefined}
        className={`text-xs uppercase tracking-wide text-gray-500 px-3 py-2 bg-gray-900/50 flex items-center gap-2 select-none ${
          sectionKey ? "cursor-pointer hover:bg-gray-800" : ""
        }`}
      >
        {sectionKey && (
          <span className="text-[10px] text-gray-500">{collapsed ? "\u203A" : "\u2039"}</span>
        )}
        <span>{label}</span>
        <span className="ml-auto bg-gray-700 text-gray-300 px-1.5 py-0.5 rounded-full text-[10px] font-medium">
          {count}
        </span>
      </div>
    );
  };

  return (
    <div ref={scrollRef} className="divide-y divide-gray-700 max-h-[calc(100vh-12rem)] overflow-y-auto">
      {renderSectionHeader("Active", activeBeans.length, "active")}
      <div
        className="grid transition-[grid-template-rows] duration-200 ease-in-out"
        style={{ gridTemplateRows: collapsedSections.active ? "0fr" : "1fr" }}
      >
        <div className="overflow-hidden">
          {activeBeans.length === 0 ? (
            <div className="px-3 py-4 text-sm text-gray-500 text-center">
              No active beans — thaw or import beans to continue.
            </div>
          ) : (
            activeBeans.map((bean) => renderBean(bean, true))
          )}
        </div>
      </div>

      {renderSectionHeader("Frozen", frozenBeans.length, "frozen")}
      <div
        className="grid transition-[grid-template-rows] duration-200 ease-in-out"
        style={{ gridTemplateRows: collapsedSections.frozen ? "0fr" : "1fr" }}
      >
        <div className="overflow-hidden">
          {frozenBeans.map((bean) => renderBean(bean, false))}
        </div>
      </div>
    </div>
  );
}
