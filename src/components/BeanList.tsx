"use client";

import { useState, useCallback, useMemo } from "react";
import useSWR, { mutate } from "swr";
import { BeanWithComputed, ScheduleDay } from "@/lib/types";
import { getRoasterColor } from "@/lib/colors";
import { daysBetween } from "@/lib/date-utils";
import { extractBeanFinishDates } from "@/lib/schedule-utils";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

function statusColor(bean: BeanWithComputed): string {
  if (bean.remaining_grams <= 0) return "bg-gray-200 text-gray-500";
  if (bean.is_frozen) return "bg-blue-100 text-blue-800";
  if (!bean.ready_date) return "bg-yellow-100 text-yellow-800";
  const today = new Date().toISOString().split("T")[0];
  if (bean.ready_date > today) return "bg-orange-100 text-orange-800";
  return "bg-green-100 text-green-800";
}

function statusLabel(bean: BeanWithComputed): string {
  if (bean.remaining_grams <= 0) return "Depleted";
  if (bean.is_frozen) {
    if (bean.planned_thaw_date) return `Thaw ${bean.planned_thaw_date}`;
    return "Frozen";
  }
  if (!bean.ready_date) return "No roast date";
  const today = new Date().toISOString().split("T")[0];
  if (bean.ready_date > today) return "Resting";
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

  const freezeSuggestions = useMemo(() => {
    const suggestions = new Map<string, string>();
    if (!beans || !schedule) return suggestions;

    const todayStr = new Date().toISOString().split("T")[0];

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

  if (error)
    return <div className="p-4 text-red-600">Failed to load beans</div>;
  if (!beans) return <div className="p-4 text-gray-500">Loading...</div>;

  if (beans.length === 0) {
    return (
      <div className="p-4 text-gray-500 text-center">
        <p className="mb-2">No beans imported yet.</p>
        <p className="text-sm">Use the Import button to get started.</p>
      </div>
    );
  }

  return (
    <div className="divide-y divide-gray-100">
      {beans.map((bean) => {
        const roasterColor = getRoasterColor(bean.roaster);
        return (
          <div
            key={bean.id}
            draggable
            onDragStart={(e) => handleDragStart(e, bean.id)}
            onDragOver={(e) => handleDragOver(e, bean.id)}
            onDrop={(e) => handleDrop(e, bean.id)}
            onDragEnd={() => {
              setDragOverId(null);
              setDragId(null);
            }}
            onClick={() => onSelectBean(bean.id)}
            className={`w-full text-left p-3 hover:bg-gray-50 transition-colors cursor-grab active:cursor-grabbing ${
              selectedBeanId === bean.id
                ? "bg-amber-50 border-l-2 border-amber-600"
                : ""
            } ${dragOverId === bean.id ? "bg-amber-50/50 border-t-2 border-amber-400" : ""}`}
          >
            <div className="flex justify-between items-start">
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-gray-900 truncate">
                  {bean.name}
                </p>
                <p className="text-xs text-gray-500 truncate">
                  <span
                    className="inline-block w-2 h-2 rounded-full mr-1"
                    style={{ backgroundColor: roasterColor.border }}
                  />
                  {bean.roaster}
                </p>
              </div>
              <span
                className={`ml-2 px-2 py-0.5 rounded-full text-xs font-medium shrink-0 ${statusColor(bean)}`}
              >
                {statusLabel(bean)}
              </span>
            </div>
            <div className="mt-1 flex gap-3 text-xs text-gray-500">
              <span>{Math.round(bean.remaining_grams)}g remaining</span>
              {bean.ready_date && <span>Ready {bean.ready_date}</span>}
            </div>
            {(ageAtFinish.get(bean.id) ?? 0) > 60 && (
              <p className="mt-0.5 text-xs font-medium text-red-600">
                Finishes day {ageAtFinish.get(bean.id)}
              </p>
            )}
            {freezeSuggestions.has(bean.id) && (
              <p className="mt-0.5 text-xs font-medium text-blue-600">
                {freezeSuggestions.get(bean.id)}
              </p>
            )}
          </div>
        );
      })}
    </div>
  );
}
