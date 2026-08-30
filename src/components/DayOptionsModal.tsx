"use client";

import { useState, useEffect } from "react";
import { ConsumptionOverride } from "@/lib/types";
import Modal from "./Modal";

interface DayOptionsModalProps {
  date: string;
  isSkipDay: boolean;
  existingOverride: ConsumptionOverride | null;
  onClose: () => void;
  onToggleSkip: (date: string) => Promise<void>;
  onSaveOverride: (override: {
    start_date: string;
    end_date: string;
    daily_grams: number;
    dose_size_grams: number;
  }) => Promise<void>;
  onClearOverride: (id: number) => Promise<void>;
}

const inputClass =
  "h-11 w-full rounded-[9px] border border-rule-strong bg-[#191614] px-3 font-mono text-[13.5px] tabular-nums text-ink focus:border-accent-dim focus:outline-none lg:h-[38px]";

export default function DayOptionsModal({
  date,
  isSkipDay,
  existingOverride,
  onClose,
  onToggleSkip,
  onSaveOverride,
  onClearOverride,
}: DayOptionsModalProps) {
  const [dailyGrams, setDailyGrams] = useState(
    existingOverride?.daily_grams?.toString() || "40"
  );
  const [doseSize, setDoseSize] = useState(
    existingOverride?.dose_size_grams?.toString() || "20"
  );
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (existingOverride) {
      setDailyGrams(existingOverride.daily_grams.toString());
      setDoseSize(existingOverride.dose_size_grams.toString());
    }
  }, [existingOverride]);

  const formattedDate = new Date(date + "T00:00:00").toLocaleDateString(
    undefined,
    { weekday: "long", day: "numeric", month: "long" }
  );

  const handleSaveOverride = async () => {
    const grams = parseFloat(dailyGrams);
    const dose = parseFloat(doseSize);
    if (isNaN(grams) || isNaN(dose) || grams <= 0 || dose <= 0) return;

    setSaving(true);
    try {
      if (existingOverride?.id) {
        await onClearOverride(existingOverride.id);
      }
      await onSaveOverride({
        start_date: date,
        end_date: date,
        daily_grams: grams,
        dose_size_grams: dose,
      });
      onClose();
    } finally {
      setSaving(false);
    }
  };

  const handleClearOverride = async () => {
    if (!existingOverride?.id) return;
    setSaving(true);
    try {
      await onClearOverride(existingOverride.id);
      onClose();
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title={formattedDate} subtitle={date} onClose={onClose}>
      <div className="flex flex-col gap-[18px] px-[18px] pb-[18px] pt-4">
        {/* Skip day */}
        <button
          onClick={async () => {
            await onToggleSkip(date);
            onClose();
          }}
          className="flex items-center gap-3 rounded-[10px] border border-rule bg-raised p-3 text-left transition-colors hover:bg-elevated"
        >
          <div className="flex-1">
            <div className="text-[13px] font-medium">Skip this day</div>
            <p className="mt-0.5 text-[11.5px] leading-[1.5] text-ink-faint text-pretty">
              Travelling, or away from the grinder. Nothing is consumed and
              everything after shifts a day later.
            </p>
          </div>
          <span
            className={`flex h-[23px] w-10 shrink-0 items-center rounded-full p-0.5 transition-colors ${
              isSkipDay ? "justify-end bg-accent" : "bg-track"
            }`}
          >
            <span
              className={`h-[19px] w-[19px] rounded-full ${isSkipDay ? "bg-on-accent" : "bg-ink-faint"}`}
            />
          </span>
        </button>

        {/* Consumption override */}
        <div className="flex flex-col gap-3">
          <div className="flex items-baseline justify-between">
            <span className="text-[10.5px] uppercase tracking-[0.09em] text-ink-faint">
              Drink more or less
            </span>
            {existingOverride && (
              <span className="font-mono text-[11.5px] tabular-nums text-ink-faint">
                override set
              </span>
            )}
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label
                htmlFor="daily-grams"
                className="mb-1.5 block text-[11.5px] text-ink-muted"
              >
                Total for the day
              </label>
              <input
                id="daily-grams"
                type="number"
                value={dailyGrams}
                onChange={(e) => setDailyGrams(e.target.value)}
                className={inputClass}
                min="1"
                step="1"
              />
            </div>
            <div>
              <label
                htmlFor="dose-size"
                className="mb-1.5 block text-[11.5px] text-ink-muted"
              >
                Dose size
              </label>
              <input
                id="dose-size"
                type="number"
                value={doseSize}
                onChange={(e) => setDoseSize(e.target.value)}
                className={inputClass}
                min="1"
                step="1"
              />
            </div>
          </div>
          <div className="flex gap-2.5">
            <button
              onClick={handleSaveOverride}
              disabled={saving}
              className="h-11 flex-1 rounded-[9px] bg-accent text-[13px] font-semibold text-on-accent transition-colors hover:bg-[#f0b878] disabled:opacity-50 lg:h-[38px]"
            >
              {existingOverride ? "Update" : "Set"} override
            </button>
            {existingOverride && (
              <button
                onClick={handleClearOverride}
                disabled={saving}
                className="h-11 rounded-[9px] border border-rule-strong px-3.5 text-[13px] text-ink-muted transition-colors hover:bg-elevated hover:text-ink disabled:opacity-50 lg:h-[38px]"
              >
                Clear
              </button>
            )}
          </div>
        </div>
      </div>
    </Modal>
  );
}
