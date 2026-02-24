"use client";

import { useState, useEffect } from "react";
import useSWR, { mutate } from "swr";
import { SkipDayRange } from "@/lib/types";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

interface RoasterDefault {
  roaster: string;
  rest_days: number;
}

export default function SettingsPanel({
  isOpen,
  onClose,
}: {
  isOpen: boolean;
  onClose: () => void;
}) {
  const { data } = useSWR(isOpen ? "/api/settings" : null, fetcher);
  const { data: skipDayRanges, mutate: mutateSkipDays } = useSWR<SkipDayRange[]>(
    isOpen ? "/api/skip-days" : null,
    fetcher
  );
  const [dailyGrams, setDailyGrams] = useState(45);
  const [defaultRestDays, setDefaultRestDays] = useState(30);
  const [roasterDefaults, setRoasterDefaults] = useState<RoasterDefault[]>([]);
  const [newRoaster, setNewRoaster] = useState("");
  const [newRestDays, setNewRestDays] = useState(30);
  const [newSkipStart, setNewSkipStart] = useState("");
  const [newSkipEnd, setNewSkipEnd] = useState("");
  const [newSkipReason, setNewSkipReason] = useState("");
  const [editingSkipId, setEditingSkipId] = useState<number | null>(null);
  const [editSkipStart, setEditSkipStart] = useState("");
  const [editSkipEnd, setEditSkipEnd] = useState("");
  const [editSkipReason, setEditSkipReason] = useState("");

  useEffect(() => {
    if (data) {
      setDailyGrams(data.daily_consumption_grams);
      setDefaultRestDays(data.default_rest_days);
      setRoasterDefaults(data.roaster_defaults || []);
    }
  }, [data]);

  if (!isOpen) return null;

  const handleSave = async () => {
    await fetch("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        daily_consumption_grams: dailyGrams,
        default_rest_days: defaultRestDays,
        roaster_defaults: roasterDefaults,
      }),
    });
    mutate("/api/settings");
    mutate("/api/beans");
    mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
      revalidate: true,
    });
    onClose();
  };

  const addRoasterDefault = () => {
    if (newRoaster.trim()) {
      setRoasterDefaults([
        ...roasterDefaults.filter((r) => r.roaster !== newRoaster.trim()),
        { roaster: newRoaster.trim(), rest_days: newRestDays },
      ]);
      setNewRoaster("");
    }
  };

  const revalidateSchedule = () => {
    mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
      revalidate: true,
    });
  };

  const addSkipDayRange = async () => {
    if (!newSkipStart || !newSkipEnd) return;
    await fetch("/api/skip-days", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        start_date: newSkipStart,
        end_date: newSkipEnd,
        reason: newSkipReason || null,
      }),
    });
    setNewSkipStart("");
    setNewSkipEnd("");
    setNewSkipReason("");
    mutateSkipDays();
    revalidateSchedule();
  };

  const deleteSkipDayRange = async (id: number) => {
    await fetch(`/api/skip-days/${id}`, { method: "DELETE" });
    mutateSkipDays();
    revalidateSchedule();
  };

  const startEditingSkip = (range: SkipDayRange) => {
    setEditingSkipId(range.id!);
    setEditSkipStart(range.start_date);
    setEditSkipEnd(range.end_date);
    setEditSkipReason(range.reason || "");
  };

  const saveEditSkip = async () => {
    if (!editingSkipId || !editSkipStart || !editSkipEnd) return;
    await fetch(`/api/skip-days/${editingSkipId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        start_date: editSkipStart,
        end_date: editSkipEnd,
        reason: editSkipReason || null,
      }),
    });
    setEditingSkipId(null);
    mutateSkipDays();
    revalidateSchedule();
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-white rounded-xl shadow-xl p-6 w-full max-w-lg mx-4">
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-lg font-semibold text-gray-900">Settings</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600"
          >
            ✕
          </button>
        </div>

        <div className="space-y-6">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Daily consumption (grams)
            </label>
            <input
              type="number"
              value={dailyGrams}
              onChange={(e) => setDailyGrams(Number(e.target.value))}
              className="w-full border border-gray-300 rounded-lg px-3 py-2 text-gray-900"
              min={1}
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Default rest days
            </label>
            <input
              type="number"
              value={defaultRestDays}
              onChange={(e) => setDefaultRestDays(Number(e.target.value))}
              className="w-full border border-gray-300 rounded-lg px-3 py-2 text-gray-900"
              min={0}
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Per-roaster rest days
            </label>
            {roasterDefaults.length > 0 && (
              <div className="space-y-2 mb-3">
                {roasterDefaults.map((rd) => (
                  <div
                    key={rd.roaster}
                    className="flex items-center justify-between bg-gray-50 rounded-lg px-3 py-2"
                  >
                    <span className="text-sm text-gray-900">{rd.roaster}</span>
                    <div className="flex items-center gap-2">
                      <input
                        type="number"
                        value={rd.rest_days}
                        onChange={(e) =>
                          setRoasterDefaults(
                            roasterDefaults.map((r) =>
                              r.roaster === rd.roaster
                                ? { ...r, rest_days: Number(e.target.value) }
                                : r
                            )
                          )
                        }
                        className="w-16 border border-gray-300 rounded px-2 py-1 text-sm text-gray-900"
                        min={0}
                      />
                      <span className="text-xs text-gray-500">days</span>
                      <button
                        onClick={() =>
                          setRoasterDefaults(
                            roasterDefaults.filter(
                              (r) => r.roaster !== rd.roaster
                            )
                          )
                        }
                        className="text-red-400 hover:text-red-600 text-sm"
                      >
                        ✕
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
            <div className="flex gap-2">
              <input
                type="text"
                value={newRoaster}
                onChange={(e) => setNewRoaster(e.target.value)}
                placeholder="Roaster name"
                className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900"
              />
              <input
                type="number"
                value={newRestDays}
                onChange={(e) => setNewRestDays(Number(e.target.value))}
                className="w-16 border border-gray-300 rounded px-2 py-2 text-sm text-gray-900"
                min={0}
              />
              <button
                onClick={addRoasterDefault}
                className="px-3 py-2 bg-gray-200 rounded-lg text-sm hover:bg-gray-300 text-gray-900"
              >
                Add
              </button>
            </div>
          </div>

          {/* Skip Days */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Skip days
            </label>
            {skipDayRanges && skipDayRanges.length > 0 && (
              <div className="space-y-2 mb-3">
                {skipDayRanges.map((range) => (
                  <div
                    key={range.id}
                    className="bg-amber-50 border border-amber-200 rounded-lg px-3 py-2"
                  >
                    {editingSkipId === range.id ? (
                      <div className="space-y-2">
                        <div className="flex gap-2">
                          <input
                            type="date"
                            value={editSkipStart}
                            onChange={(e) => setEditSkipStart(e.target.value)}
                            className="flex-1 border border-gray-300 rounded px-2 py-1 text-sm text-gray-900"
                          />
                          <input
                            type="date"
                            value={editSkipEnd}
                            onChange={(e) => setEditSkipEnd(e.target.value)}
                            className="flex-1 border border-gray-300 rounded px-2 py-1 text-sm text-gray-900"
                          />
                        </div>
                        <div className="flex gap-2">
                          <input
                            type="text"
                            value={editSkipReason}
                            onChange={(e) => setEditSkipReason(e.target.value)}
                            placeholder="Reason (optional)"
                            className="flex-1 border border-gray-300 rounded px-2 py-1 text-sm text-gray-900"
                          />
                          <button
                            onClick={saveEditSkip}
                            className="px-2 py-1 bg-amber-600 text-white rounded text-sm hover:bg-amber-700"
                          >
                            Save
                          </button>
                          <button
                            onClick={() => setEditingSkipId(null)}
                            className="px-2 py-1 text-gray-500 hover:text-gray-700 text-sm"
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    ) : (
                      <div className="flex items-center justify-between">
                        <button
                          onClick={() => startEditingSkip(range)}
                          className="text-left flex-1"
                        >
                          <span className="text-sm text-amber-900 font-medium">
                            {range.start_date} to {range.end_date}
                          </span>
                          {range.reason && (
                            <span className="text-sm text-amber-700 ml-2">
                              ({range.reason})
                            </span>
                          )}
                        </button>
                        <button
                          onClick={() => deleteSkipDayRange(range.id!)}
                          className="text-red-400 hover:text-red-600 text-sm ml-2"
                        >
                          ✕
                        </button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
            <div className="flex gap-2">
              <input
                type="date"
                value={newSkipStart}
                onChange={(e) => setNewSkipStart(e.target.value)}
                className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900"
              />
              <input
                type="date"
                value={newSkipEnd}
                onChange={(e) => setNewSkipEnd(e.target.value)}
                className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900"
              />
            </div>
            <div className="flex gap-2 mt-2">
              <input
                type="text"
                value={newSkipReason}
                onChange={(e) => setNewSkipReason(e.target.value)}
                placeholder="Reason (optional)"
                className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900"
              />
              <button
                onClick={addSkipDayRange}
                className="px-3 py-2 bg-gray-200 rounded-lg text-sm hover:bg-gray-300 text-gray-900"
              >
                Add
              </button>
            </div>
          </div>
        </div>

        <div className="flex justify-end gap-3 mt-6">
          <button
            onClick={onClose}
            className="px-4 py-2 text-gray-600 hover:text-gray-800"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            className="px-4 py-2 bg-amber-700 text-white rounded-lg hover:bg-amber-800"
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
