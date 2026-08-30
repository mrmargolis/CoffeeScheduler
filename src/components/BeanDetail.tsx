"use client";

import { useState, useEffect, useMemo } from "react";
import useSWR, { mutate } from "swr";
import { ScheduleDay } from "@/lib/types";
import {
  daysBetween,
  today as getToday,
  scheduleKey,
  formatShortDay,
} from "@/lib/date-utils";
import { effectiveAge } from "@/lib/freeze-utils";
import {
  extractBeanFinishDates,
  extractBeanStartDates,
} from "@/lib/schedule-utils";
import { useRoasterColors } from "@/lib/use-roaster-colors";
import { ChevronLeft, CloseIcon, SnowflakeIcon } from "./icons";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

const inputClass =
  "w-full rounded-lg border border-rule-strong bg-[#191614] px-3 font-mono text-[13.5px] tabular-nums text-ink placeholder:font-sans placeholder:text-ink-faint focus:border-accent-dim focus:outline-none h-11 lg:h-9";

const labelClass = "mb-1.5 block text-[11.5px] text-ink-muted";

export default function BeanDetail({
  beanId,
  onClose,
}: {
  beanId: string;
  onClose: () => void;
}) {
  const { data: bean, error } = useSWR(`/api/beans/${beanId}`, fetcher);
  const { data: settings } = useSWR("/api/settings", fetcher);
  const { data: schedule } = useSWR<ScheduleDay[]>(scheduleKey(), fetcher);
  const colorFor = useRoasterColors();
  const [restDays, setRestDays] = useState<string>("");
  const [roastDate, setRoastDate] = useState("");
  const [plannedThawDate, setPlannedThawDate] = useState("");
  const [freezeAfterGrams, setFreezeAfterGrams] = useState<string>("");
  const [freezeConfirm, setFreezeConfirm] = useState(false);

  useEffect(() => {
    if (bean) {
      setRestDays(bean.rest_days !== null ? String(bean.rest_days) : "");
      setRoastDate(bean.roast_date || "");
      setPlannedThawDate(bean.planned_thaw_date || "");
      setFreezeAfterGrams(
        bean.freeze_after_grams != null ? String(bean.freeze_after_grams) : ""
      );
    }
  }, [bean]);

  const window_ = useMemo(() => {
    if (!schedule || !bean) return { start: null, finish: null };
    return {
      start: extractBeanStartDates(schedule).get(bean.id) ?? null,
      finish: extractBeanFinishDates(schedule).get(bean.id) ?? null,
    };
  }, [schedule, bean]);

  if (error)
    return (
      <div className="p-4 text-[13px] text-alert">Failed to load bag details</div>
    );
  if (!bean)
    return <div className="p-4 text-[13px] text-ink-faint">Loading…</div>;

  const handleSave = async () => {
    await fetch(`/api/beans/${beanId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        rest_days: restDays === "" ? null : Number(restDays),
        roast_date: roastDate || null,
        planned_thaw_date: plannedThawDate || null,
        freeze_after_grams:
          freezeAfterGrams === "" ? null : Number(freezeAfterGrams),
      }),
    });
    mutate(`/api/beans/${beanId}`);
    mutate("/api/beans");
    mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
      revalidate: true,
    });
    onClose();
  };

  const handleFreeze = async () => {
    await fetch(`/api/beans/${beanId}/freeze`, { method: "POST" });
    mutate(`/api/beans/${beanId}`);
    mutate("/api/beans");
    mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
      revalidate: true,
    });
    onClose();
  };

  const rail = colorFor(bean.roaster).border;
  const consumed = Math.max(0, bean.weight_grams - bean.remaining_grams);
  const pctConsumed =
    bean.weight_grams > 0
      ? Math.min(100, (consumed / bean.weight_grams) * 100)
      : 0;
  const daysLeft =
    settings?.daily_consumption_grams > 0 && bean.remaining_grams > 0
      ? Math.round(bean.remaining_grams / settings.daily_consumption_grams)
      : null;
  const currentAge = bean.roast_date
    ? effectiveAge(bean.roast_date, getToday(), bean.frozen_days ?? 0)
    : null;
  const finishAge =
    bean.roast_date && window_.finish
      ? effectiveAge(bean.roast_date, window_.finish, bean.frozen_days ?? 0)
      : null;

  const origin = [bean.country, bean.region].filter(Boolean).join(", ");
  const provenance = [origin, bean.variety, bean.processing]
    .filter(Boolean)
    .join(" · ");

  // Age bar: roast → ready → last cup, as fractions of the whole life.
  const ageTrack = (() => {
    if (!bean.roast_date || !bean.ready_date) return null;
    const end = window_.finish ?? getToday();
    const total = daysBetween(bean.roast_date, end);
    if (total <= 0) return null;
    const restPct = Math.min(
      100,
      (daysBetween(bean.roast_date, bean.ready_date) / total) * 100
    );
    const todayPct = Math.max(
      0,
      Math.min(100, (daysBetween(bean.roast_date, getToday()) / total) * 100)
    );
    return { restPct, todayPct, end };
  })();

  return (
    <div>
      {/* Header */}
      <div className="flex items-center gap-2.5 border-b border-rule bg-raised px-3.5 py-3">
        <button
          onClick={onClose}
          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-ink-muted transition-colors hover:bg-elevated hover:text-ink"
          aria-label="Back to backlog"
        >
          <ChevronLeft />
        </button>
        <span className="text-[12px] text-ink-muted">Back to backlog</span>
        <button
          onClick={onClose}
          className="ml-auto flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-ink-faint transition-colors hover:bg-elevated hover:text-ink"
          aria-label="Close"
        >
          <CloseIcon size={15} />
        </button>
      </div>

      <div className="flex flex-col gap-5 p-4 lg:p-[18px]">
        {/* Identity */}
        <div className="flex flex-col gap-2.5">
          <div className="flex items-start gap-3">
            <span
              className="w-[3px] shrink-0 self-stretch rounded-sm"
              style={{ backgroundColor: rail, minHeight: 40 }}
            />
            <div className="min-w-0 flex-1">
              <h1 className="text-[20px] font-semibold leading-[1.2] tracking-[-0.02em] text-pretty">
                {bean.name}
              </h1>
              <p className="mt-1 text-[13px] text-ink-muted">
                {provenance ? `${bean.roaster} · ${provenance}` : bean.roaster}
              </p>
            </div>
          </div>
          {bean.flavour_profile && (
            <p className="text-[12.5px] leading-[1.5] text-ink-muted text-pretty">
              {bean.flavour_profile}
            </p>
          )}
        </div>

        {/* Consumption meter */}
        <div className="flex flex-col gap-2.5 rounded-[10px] bg-raised p-3.5">
          <div className="flex items-baseline justify-between gap-3">
            <div className="flex items-baseline gap-1.5">
              <span className="font-mono text-[25px] font-medium leading-none tabular-nums">
                {Math.round(bean.remaining_grams)}
              </span>
              <span className="font-mono text-[13px] text-ink-faint">
                g of {bean.weight_grams} left
              </span>
            </div>
            {daysLeft !== null && (
              <span className="font-mono text-[12px] tabular-nums text-ink-muted">
                ≈ {daysLeft} more {daysLeft === 1 ? "day" : "days"}
              </span>
            )}
          </div>
          <div className="h-1.5 overflow-hidden rounded-full bg-track">
            <div
              className="h-full rounded-full bg-accent"
              style={{ width: `${pctConsumed}%` }}
            />
          </div>
          <div className="flex items-center justify-between font-mono text-[11px] tabular-nums text-ink-faint">
            <span>{Math.round(bean.total_brewed_grams)} g brewed</span>
            {window_.start && window_.finish && (
              <span>
                {formatShortDay(window_.start)} → {formatShortDay(window_.finish)}
              </span>
            )}
          </div>
        </div>

        {/* Age */}
        {ageTrack && (
          <div className="flex flex-col gap-2.5">
            <span className="text-[10.5px] uppercase tracking-[0.09em] text-ink-faint">
              Age
            </span>
            <div className="relative h-[26px]">
              <div className="absolute inset-x-0 top-2 h-1 rounded-full bg-track" />
              <div
                className="absolute top-2 h-1 rounded-l-full bg-[#4b423a]"
                style={{ left: 0, width: `${ageTrack.restPct}%` }}
              />
              <div
                className="absolute top-2 h-1 bg-accent"
                style={{
                  left: `${ageTrack.restPct}%`,
                  width: `${Math.max(0, ageTrack.todayPct - ageTrack.restPct)}%`,
                }}
              />
              <div
                className="absolute top-1 h-3 w-0.5 bg-ink-muted"
                style={{ left: `${ageTrack.todayPct}%` }}
              />
            </div>
            <div className="flex items-baseline justify-between font-mono text-[11px] tabular-nums text-ink-faint">
              <span>Roasted {formatShortDay(bean.roast_date)}</span>
              <span className="text-ink-muted">
                Rested {formatShortDay(bean.ready_date)}
              </span>
              {finishAge !== null && (
                <span className={finishAge > 60 ? "text-alert" : undefined}>
                  Last cup, day {finishAge}
                </span>
              )}
            </div>
          </div>
        )}

        {/* Facts */}
        <dl className="flex flex-col">
          <Fact label="Roast date">
            {bean.roast_date ? (
              <span className="font-mono tabular-nums">{bean.roast_date}</span>
            ) : (
              <span className="text-early">Not set</span>
            )}
          </Fact>
          {currentAge !== null && (
            <Fact label="Current age">
              <span className="font-mono tabular-nums">
                {currentAge} d
                {(bean.frozen_days ?? 0) > 0 && (
                  <span className="ml-1 text-ink-faint">
                    ({daysBetween(bean.roast_date, getToday())} calendar,{" "}
                    {bean.frozen_days} frozen)
                  </span>
                )}
              </span>
            </Fact>
          )}
          <Fact label="Rest required">
            <span className="font-mono tabular-nums">
              {bean.effective_rest_days} d
            </span>
          </Fact>
          <Fact label={bean.ready_date && bean.ready_date <= getToday() ? "Ready since" : "Ready date"}>
            {bean.ready_date ? (
              <span className="font-mono tabular-nums">{bean.ready_date}</span>
            ) : (
              <span className="text-early">Unknown</span>
            )}
          </Fact>
          {!bean.is_frozen && bean.freeze_after_grams != null && (
            <Fact label="Freeze after">
              <span className="font-mono tabular-nums">
                {bean.freeze_after_grams} g consumed
              </span>
            </Fact>
          )}
          {bean.is_frozen && bean.planned_thaw_date && (
            <Fact label="Planned thaw">
              <span className="font-mono tabular-nums">
                {bean.planned_thaw_date}
              </span>
            </Fact>
          )}
        </dl>

        {/* Adjust */}
        <div className="flex flex-col gap-3">
          <span className="text-[10.5px] uppercase tracking-[0.09em] text-ink-faint">
            Adjust
          </span>

          {!bean.roast_date && (
            <div>
              <label className={labelClass} htmlFor="roast-date">
                Set roast date
              </label>
              <input
                id="roast-date"
                type="date"
                value={roastDate}
                onChange={(e) => setRoastDate(e.target.value)}
                className={inputClass}
              />
            </div>
          )}

          {bean.is_frozen && (
            <div>
              <label className={labelClass} htmlFor="thaw-date">
                Planned thaw date
              </label>
              <input
                id="thaw-date"
                type="date"
                value={plannedThawDate}
                onChange={(e) => setPlannedThawDate(e.target.value)}
                className={inputClass}
              />
            </div>
          )}

          {!bean.is_frozen && (
            <div>
              <label className={labelClass} htmlFor="freeze-after">
                Freeze automatically after (grams consumed)
              </label>
              <input
                id="freeze-after"
                type="number"
                value={freezeAfterGrams}
                onChange={(e) => setFreezeAfterGrams(e.target.value)}
                placeholder="e.g. 125"
                className={inputClass}
                min={0}
                max={bean.weight_grams}
              />
            </div>
          )}

          <div>
            <label className={labelClass} htmlFor="rest-days">
              Rest days for this bag
            </label>
            <input
              id="rest-days"
              type="number"
              value={restDays}
              onChange={(e) => setRestDays(e.target.value)}
              placeholder={`${bean.effective_rest_days} — inherited`}
              className={inputClass}
              min={0}
            />
          </div>

          <div className="mt-0.5 flex gap-2.5">
            <button
              onClick={handleSave}
              className="h-11 flex-1 rounded-[9px] bg-accent text-[13px] font-semibold text-on-accent transition-colors hover:bg-[#f0b878] lg:h-[38px]"
            >
              Save changes
            </button>
            <button
              onClick={() => {
                if (freezeConfirm) {
                  handleFreeze();
                  setFreezeConfirm(false);
                } else {
                  setFreezeConfirm(true);
                }
              }}
              onBlur={() => setFreezeConfirm(false)}
              className={`flex h-11 items-center gap-2 rounded-[9px] px-3.5 text-[13px] transition-colors lg:h-[38px] ${
                freezeConfirm
                  ? "bg-early-wash text-early"
                  : "border border-cold-line text-cold hover:bg-cold-wash"
              }`}
            >
              <SnowflakeIcon size={14} />
              {freezeConfirm
                ? "Confirm?"
                : bean.is_frozen
                  ? "Thaw"
                  : "Freeze"}
            </button>
          </div>
        </div>

        {/* Recent brews */}
        {bean.recent_brews?.length > 0 && (
          <div className="flex flex-col gap-2.5 border-t border-rule pt-4">
            <div className="flex items-baseline justify-between">
              <span className="text-[10.5px] uppercase tracking-[0.09em] text-ink-faint">
                Recent brews
              </span>
            </div>
            <div className="flex flex-col">
              {bean.recent_brews.map(
                (
                  brew: {
                    creation_date: string;
                    ground_coffee_grams: number;
                    rating: number | null;
                  },
                  i: number
                ) => (
                  <div
                    key={i}
                    className="flex items-center gap-3 border-b border-rule py-[7px] font-mono text-[12px] tabular-nums"
                  >
                    <span className="w-[74px] shrink-0 text-ink-muted">
                      {formatShortDay(brew.creation_date)}
                    </span>
                    <span className="text-ink-faint">
                      {brew.ground_coffee_grams} g
                    </span>
                    <span className="flex-1" />
                    <span className={brew.rating ? "text-accent" : "text-ink-faint"}>
                      {brew.rating ? `★ ${brew.rating}` : "—"}
                    </span>
                  </div>
                )
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function Fact({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-baseline justify-between gap-3.5 border-t border-rule py-2.5 first:border-t-0 last:border-b last:border-b-rule">
      <dt className="shrink-0 text-[12px] text-ink-faint">{label}</dt>
      <dd className="text-right text-[12.5px]">{children}</dd>
    </div>
  );
}
