"use client";

import { useState, useEffect } from "react";
import useSWR, { mutate } from "swr";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

export default function BeanDetail({
  beanId,
  onClose,
}: {
  beanId: string;
  onClose: () => void;
}) {
  const { data: bean, error } = useSWR(`/api/beans/${beanId}`, fetcher);
  const [restDays, setRestDays] = useState<string>("");
  const [notes, setNotes] = useState("");
  const [roastDate, setRoastDate] = useState("");
  const [plannedThawDate, setPlannedThawDate] = useState("");

  useEffect(() => {
    if (bean) {
      setRestDays(bean.rest_days !== null ? String(bean.rest_days) : "");
      setNotes(bean.notes || "");
      setRoastDate(bean.roast_date || "");
      setPlannedThawDate(bean.planned_thaw_date || "");
    }
  }, [bean]);

  if (error)
    return <div className="p-4 text-red-600">Failed to load bean details</div>;
  if (!bean) return <div className="p-4 text-gray-500">Loading...</div>;

  const handleSave = async () => {
    await fetch(`/api/beans/${beanId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        rest_days: restDays === "" ? null : Number(restDays),
        notes: notes || null,
        roast_date: roastDate || null,
        planned_thaw_date: plannedThawDate || null,
      }),
    });
    mutate(`/api/beans/${beanId}`);
    mutate("/api/beans");
    mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
      revalidate: true,
    });
  };

  const handleFreeze = async () => {
    await fetch(`/api/beans/${beanId}/freeze`, { method: "POST" });
    mutate(`/api/beans/${beanId}`);
    mutate("/api/beans");
    mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
      revalidate: true,
    });
  };

  return (
    <div className="p-4 space-y-4">
      <div className="flex justify-between items-start">
        <div>
          <h3 className="font-semibold text-gray-900">{bean.name}</h3>
          <p className="text-sm text-gray-500">{bean.roaster}</p>
        </div>
        <button
          onClick={onClose}
          className="text-gray-400 hover:text-gray-600"
        >
          ✕
        </button>
      </div>

      {/* Info Grid */}
      <div className="grid grid-cols-2 gap-2 text-sm">
        <div className="text-gray-500">Roast date</div>
        <div className="text-gray-900">
          {bean.roast_date || (
            <span className="text-yellow-600">Not set</span>
          )}
        </div>
        <div className="text-gray-500">Weight</div>
        <div className="text-gray-900">{bean.weight_grams}g</div>
        <div className="text-gray-500">Brewed</div>
        <div className="text-gray-900">{bean.total_brewed_grams}g</div>
        <div className="text-gray-500">Remaining</div>
        <div className="text-gray-900 font-medium">
          {Math.round(bean.remaining_grams)}g
        </div>
        <div className="text-gray-500">Effective rest</div>
        <div className="text-gray-900">{bean.effective_rest_days} days</div>
        <div className="text-gray-500">Ready date</div>
        <div className="text-gray-900">
          {bean.ready_date || <span className="text-yellow-600">Unknown</span>}
        </div>
        {bean.is_frozen && bean.planned_thaw_date && (
          <>
            <div className="text-gray-500">Planned thaw</div>
            <div className="text-gray-900">{bean.planned_thaw_date}</div>
          </>
        )}
        {bean.flavour_profile && (
          <>
            <div className="text-gray-500">Flavour</div>
            <div className="text-gray-900">{bean.flavour_profile}</div>
          </>
        )}
        {bean.country && (
          <>
            <div className="text-gray-500">Origin</div>
            <div className="text-gray-900">
              {[bean.country, bean.region].filter(Boolean).join(", ")}
            </div>
          </>
        )}
        {bean.variety && (
          <>
            <div className="text-gray-500">Variety</div>
            <div className="text-gray-900">{bean.variety}</div>
          </>
        )}
        {bean.processing && (
          <>
            <div className="text-gray-500">Processing</div>
            <div className="text-gray-900">{bean.processing}</div>
          </>
        )}
      </div>

      {/* Roast date override (for beans without one) */}
      {!bean.roast_date && (
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Set roast date
          </label>
          <input
            type="date"
            value={roastDate}
            onChange={(e) => setRoastDate(e.target.value)}
            className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900"
          />
        </div>
      )}

      {/* Planned thaw date (only when frozen) */}
      {bean.is_frozen && (
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Planned thaw date
          </label>
          <input
            type="date"
            value={plannedThawDate}
            onChange={(e) => setPlannedThawDate(e.target.value)}
            className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900"
          />
        </div>
      )}

      {/* Rest days override */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Rest days override
        </label>
        <input
          type="number"
          value={restDays}
          onChange={(e) => setRestDays(e.target.value)}
          placeholder={`Default: ${bean.effective_rest_days}`}
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900"
          min={0}
        />
      </div>

      {/* Notes */}
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Notes
        </label>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          rows={2}
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900"
        />
      </div>

      <button
        onClick={handleSave}
        className="w-full px-4 py-2 bg-amber-700 text-white rounded-lg hover:bg-amber-800 text-sm"
      >
        Save Changes
      </button>

      {/* Freeze toggle */}
      <button
        onClick={handleFreeze}
        className={`w-full px-4 py-2 rounded-lg text-sm ${
          bean.is_frozen
            ? "bg-blue-100 text-blue-800 hover:bg-blue-200"
            : "bg-gray-100 text-gray-700 hover:bg-gray-200"
        }`}
      >
        {bean.is_frozen ? "Thaw Bean" : "Freeze Bean"}
      </button>

      {/* Recent brews */}
      {bean.recent_brews?.length > 0 && (
        <div className="border-t border-gray-200 pt-4">
          <p className="text-sm font-medium text-gray-700 mb-2">
            Recent Brews
          </p>
          <div className="space-y-1">
            {bean.recent_brews.map((brew: any, i: number) => (
              <div key={i} className="flex text-xs text-gray-500">
                <span className="w-24">{brew.creation_date}</span>
                <span className="flex-1 text-center">{brew.ground_coffee_grams}g</span>
                <span className="w-10 text-right">{brew.rating ? `★${brew.rating}` : ""}</span>
              </div>
            ))}
          </div>
        </div>
      )}

    </div>
  );
}
