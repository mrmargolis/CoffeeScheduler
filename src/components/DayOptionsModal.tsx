"use client";

import { useState, useEffect } from "react";
import { ConsumptionOverride } from "@/lib/types";

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
    { weekday: "short", month: "short", day: "numeric" }
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
    <div
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      onClick={onClose}
    >
      <div
        className="bg-gray-900 rounded-xl shadow-xl p-6 w-full max-w-sm mx-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex justify-between items-center mb-4">
          <h2 className="text-lg font-semibold text-gray-300">
            {formattedDate}
          </h2>
          <button
            onClick={onClose}
            className="text-gray-500 hover:text-gray-300"
          >
            ✕
          </button>
        </div>

        {/* Skip day toggle */}
        <button
          onClick={async () => {
            await onToggleSkip(date);
            onClose();
          }}
          className={`w-full mb-4 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
            isSkipDay
              ? "bg-amber-700 text-white hover:bg-amber-800"
              : "bg-gray-800 text-gray-300 hover:bg-gray-700 border border-gray-600"
          }`}
        >
          {isSkipDay ? "Remove Skip Day" : "Mark as Skip Day"}
        </button>

        {/* Consumption override */}
        <div className="border-t border-gray-700 pt-4">
          <h3 className="text-sm font-medium text-gray-400 mb-3">
            Consumption Override
          </h3>
          <div className="grid grid-cols-2 gap-3 mb-3">
            <div>
              <label className="block text-xs text-gray-500 mb-1">
                Daily grams
              </label>
              <input
                type="number"
                value={dailyGrams}
                onChange={(e) => setDailyGrams(e.target.value)}
                className="w-full bg-gray-800 border border-gray-600 rounded px-3 py-1.5 text-sm text-gray-200 focus:border-amber-500 focus:outline-none"
                min="1"
                step="1"
              />
            </div>
            <div>
              <label className="block text-xs text-gray-500 mb-1">
                Dose size (g)
              </label>
              <input
                type="number"
                value={doseSize}
                onChange={(e) => setDoseSize(e.target.value)}
                className="w-full bg-gray-800 border border-gray-600 rounded px-3 py-1.5 text-sm text-gray-200 focus:border-amber-500 focus:outline-none"
                min="1"
                step="1"
              />
            </div>
          </div>
          <div className="flex gap-2">
            <button
              onClick={handleSaveOverride}
              disabled={saving}
              className="flex-1 px-4 py-2 bg-amber-600 text-white rounded-lg text-sm font-medium hover:bg-amber-700 transition-colors disabled:opacity-50"
            >
              {existingOverride ? "Update" : "Set"} Override
            </button>
            {existingOverride && (
              <button
                onClick={handleClearOverride}
                disabled={saving}
                className="px-4 py-2 bg-gray-800 text-gray-300 rounded-lg text-sm font-medium hover:bg-gray-700 border border-gray-600 transition-colors disabled:opacity-50"
              >
                Clear
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
