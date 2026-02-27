"use client";

import { useState, useEffect } from "react";
import useSWR, { mutate } from "swr";
import { daysBetween } from "@/lib/date-utils";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

export default function BeanDetail({
  beanId,
  onClose,
}: {
  beanId: string;
  onClose: () => void;
}) {
  const { data: bean, error } = useSWR(`/api/beans/${beanId}`, fetcher);
  const { data: settings } = useSWR("/api/settings", fetcher);
  const [restDays, setRestDays] = useState<string>("");
  const [roastDate, setRoastDate] = useState("");
  const [plannedThawDate, setPlannedThawDate] = useState("");
  const [freezeConfirm, setFreezeConfirm] = useState(false);

  useEffect(() => {
    if (bean) {
      setRestDays(bean.rest_days !== null ? String(bean.rest_days) : "");
      setRoastDate(bean.roast_date || "");
      setPlannedThawDate(bean.planned_thaw_date || "");
    }
  }, [bean]);

  if (error)
    return <div className="p-4 text-red-400">Failed to load bean details</div>;
  if (!bean) return <div className="p-4 text-gray-400">Loading...</div>;

  const handleSave = async () => {
    await fetch(`/api/beans/${beanId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        rest_days: restDays === "" ? null : Number(restDays),
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
          <h3 className="font-semibold text-gray-300">{bean.name}</h3>
          <p className="text-sm text-gray-400">{bean.roaster}</p>
        </div>
        <button
          onClick={onClose}
          className="text-gray-500 hover:text-gray-300"
        >
          ✕
        </button>
      </div>

      {/* Info Grid */}
      <div className="grid grid-cols-2 gap-2 text-sm">
        <div className="text-gray-400">Roast date</div>
        <div className="text-gray-300">
          {bean.roast_date || (
            <span className="text-yellow-400">Not set</span>
          )}
        </div>
        {bean.roast_date && (
          <>
            <div className="text-gray-400">Current age</div>
            <div className="text-gray-300">
              {daysBetween(bean.roast_date, new Date().toISOString().split("T")[0])} days
            </div>
          </>
        )}
        <div className="text-gray-400">Weight</div>
        <div className="text-gray-300">{bean.weight_grams}g</div>
        <div className="text-gray-400">Brewed</div>
        <div className="text-gray-300">{bean.total_brewed_grams}g</div>
        <div className="text-gray-400">Remaining</div>
        <div className="text-gray-300 font-medium">
          {Math.round(bean.remaining_grams)}g
          {settings?.daily_consumption_grams > 0 && bean.remaining_grams > 0 && (
            <span className="text-gray-500 font-normal ml-1">
              (~{Math.round(bean.remaining_grams / settings.daily_consumption_grams)} days)
            </span>
          )}
        </div>
        <div className="text-gray-400">Effective rest</div>
        <div className="text-gray-300">{bean.effective_rest_days} days</div>
        <div className="text-gray-400">Ready date</div>
        <div className="text-gray-300">
          {bean.ready_date || <span className="text-yellow-400">Unknown</span>}
        </div>
        {bean.is_frozen && bean.planned_thaw_date && (
          <>
            <div className="text-gray-400">Planned thaw</div>
            <div className="text-gray-300">{bean.planned_thaw_date}</div>
          </>
        )}
        {bean.flavour_profile && (
          <>
            <div className="text-gray-400">Flavour</div>
            <div className="text-gray-300">{bean.flavour_profile}</div>
          </>
        )}
        {bean.country && (
          <>
            <div className="text-gray-400">Origin</div>
            <div className="text-gray-300">
              {[bean.country, bean.region].filter(Boolean).join(", ")}
            </div>
          </>
        )}
        {bean.variety && (
          <>
            <div className="text-gray-400">Variety</div>
            <div className="text-gray-300">{bean.variety}</div>
          </>
        )}
        {bean.processing && (
          <>
            <div className="text-gray-400">Processing</div>
            <div className="text-gray-300">{bean.processing}</div>
          </>
        )}
      </div>

      {/* Roast date override (for beans without one) */}
      {!bean.roast_date && (
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-1">
            Set roast date
          </label>
          <input
            type="date"
            value={roastDate}
            onChange={(e) => setRoastDate(e.target.value)}
            className="w-full border border-gray-700 bg-gray-800 rounded-lg px-3 py-2 text-sm text-gray-300"
          />
        </div>
      )}

      {/* Planned thaw date (only when frozen) */}
      {bean.is_frozen && (
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-1">
            Planned thaw date
          </label>
          <input
            type="date"
            value={plannedThawDate}
            onChange={(e) => setPlannedThawDate(e.target.value)}
            className="w-full border border-gray-700 bg-gray-800 rounded-lg px-3 py-2 text-sm text-gray-300"
          />
        </div>
      )}

      {/* Rest days override */}
      <div>
        <label className="block text-sm font-medium text-gray-300 mb-1">
          Rest days override
        </label>
        <input
          type="number"
          value={restDays}
          onChange={(e) => setRestDays(e.target.value)}
          placeholder={`Default: ${bean.effective_rest_days}`}
          className="w-full border border-gray-700 bg-gray-800 rounded-lg px-3 py-2 text-sm text-gray-300"
          min={0}
        />
      </div>

      <button
        onClick={handleSave}
        className="w-full px-4 py-2 bg-amber-700 text-white rounded-lg hover:bg-amber-800 text-sm"
      >
        Save Changes
      </button>

      {/* Freeze toggle with confirmation */}
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
        className={`w-full px-4 py-2 rounded-lg text-sm ${
          freezeConfirm
            ? "bg-yellow-800 text-yellow-200 hover:bg-yellow-700"
            : bean.is_frozen
              ? "bg-blue-900/50 text-blue-300 hover:bg-blue-900"
              : "bg-gray-800 text-gray-300 hover:bg-gray-700"
        }`}
      >
        {freezeConfirm
          ? `Confirm ${bean.is_frozen ? "thaw" : "freeze"}?`
          : bean.is_frozen
            ? "Thaw Bean"
            : "Freeze Bean"}
      </button>

      {/* Recent brews */}
      {bean.recent_brews?.length > 0 && (
        <div className="border-t border-gray-700 pt-4">
          <p className="text-sm font-medium text-gray-300 mb-2">
            Recent Brews
          </p>
          <div className="space-y-1">
            {bean.recent_brews.map((brew: any, i: number) => (
              <div key={i} className="flex text-xs text-gray-400">
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
