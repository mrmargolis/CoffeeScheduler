"use client";

import { useState, useEffect } from "react";
import useSWR, { mutate } from "swr";
import { useRoasterColors } from "@/lib/use-roaster-colors";
import Modal from "./Modal";
import { CloseIcon, PlusIcon } from "./icons";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

interface RoasterDefault {
  roaster: string;
  rest_days: number;
}

const inputClass =
  "h-11 w-full rounded-[9px] border border-rule-strong bg-[#191614] px-3 font-mono text-[13.5px] tabular-nums text-ink placeholder:font-sans placeholder:text-ink-faint focus:border-accent-dim focus:outline-none lg:h-[38px]";

export default function SettingsPanel({
  isOpen,
  onClose,
}: {
  isOpen: boolean;
  onClose: () => void;
}) {
  const { data } = useSWR(isOpen ? "/api/settings" : null, fetcher);
  const colorFor = useRoasterColors();
  const [dailyGrams, setDailyGrams] = useState(45);
  const [defaultRestDays, setDefaultRestDays] = useState(30);
  const [roasterDefaults, setRoasterDefaults] = useState<RoasterDefault[]>([]);
  const [newRoaster, setNewRoaster] = useState("");
  const [newRestDays, setNewRestDays] = useState(30);

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

  return (
    <Modal title="Settings" onClose={onClose} widthClass="max-w-md">
      <div className="flex flex-col gap-[18px] px-[18px] pb-[18px] pt-4">
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label
              htmlFor="daily-consumption"
              className="mb-1.5 block text-[11.5px] text-ink-muted"
            >
              Coffee per day (grams)
            </label>
            <input
              id="daily-consumption"
              type="number"
              value={dailyGrams}
              onChange={(e) => setDailyGrams(Number(e.target.value))}
              className={inputClass}
              min={1}
            />
          </div>
          <div>
            <label
              htmlFor="default-rest"
              className="mb-1.5 block text-[11.5px] text-ink-muted"
            >
              Default rest (days)
            </label>
            <input
              id="default-rest"
              type="number"
              value={defaultRestDays}
              onChange={(e) => setDefaultRestDays(Number(e.target.value))}
              className={inputClass}
              min={0}
            />
          </div>
        </div>

        <div className="flex flex-col gap-2.5">
          <div className="flex items-baseline justify-between">
            <span className="text-[10.5px] uppercase tracking-[0.09em] text-ink-faint">
              Rest by roaster
            </span>
            <span className="text-[11.5px] text-ink-faint">
              overrides the default
            </span>
          </div>

          {roasterDefaults.length > 0 && (
            <div className="flex flex-col overflow-hidden rounded-[10px] border border-rule">
              {roasterDefaults.map((rd) => (
                <div
                  key={rd.roaster}
                  className="flex items-center gap-2.5 border-t border-rule bg-raised px-3 py-2.5 first:border-t-0"
                >
                  <span
                    className="h-1.5 w-1.5 shrink-0 rounded-full"
                    style={{
                      backgroundColor: colorFor(rd.roaster).border,
                    }}
                  />
                  <span className="flex-1 truncate text-[13px]">
                    {rd.roaster}
                  </span>
                  <input
                    type="number"
                    aria-label={`Rest days for ${rd.roaster}`}
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
                    className={`${inputClass} h-[30px] w-[74px] px-2.5 text-[12.5px] lg:h-[30px]`}
                    min={0}
                  />
                  <button
                    onClick={() =>
                      setRoasterDefaults(
                        roasterDefaults.filter((r) => r.roaster !== rd.roaster)
                      )
                    }
                    aria-label={`Remove ${rd.roaster}`}
                    className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-ink-faint transition-colors hover:bg-elevated hover:text-ink"
                  >
                    <CloseIcon size={14} />
                  </button>
                </div>
              ))}
            </div>
          )}

          <div className="flex gap-2.5">
            <input
              type="text"
              value={newRoaster}
              onChange={(e) => setNewRoaster(e.target.value)}
              placeholder="Add a roaster…"
              aria-label="Roaster name"
              className={`${inputClass} flex-1 font-sans`}
            />
            <input
              type="number"
              value={newRestDays}
              onChange={(e) => setNewRestDays(Number(e.target.value))}
              aria-label="Rest days"
              className={`${inputClass} w-[74px] shrink-0 px-2.5`}
              min={0}
            />
            <button
              onClick={addRoasterDefault}
              aria-label="Add roaster default"
              className="flex h-11 w-11 shrink-0 items-center justify-center rounded-[9px] border border-rule-strong text-ink-muted transition-colors hover:bg-elevated hover:text-ink lg:h-[38px] lg:w-[38px]"
            >
              <PlusIcon />
            </button>
          </div>
        </div>

        <div className="flex items-center justify-between gap-3 border-t border-rule pt-3.5">
          <p className="flex-1 text-[11.5px] leading-[1.5] text-ink-faint text-pretty">
            Doses round to 15 g. Remnants under 12 g are discarded.
          </p>
          <div className="flex shrink-0 gap-2.5">
            <button
              onClick={onClose}
              className="h-11 rounded-[9px] px-3.5 text-[13px] text-ink-muted transition-colors hover:text-ink lg:h-[38px]"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              className="h-11 rounded-[9px] bg-accent px-[18px] text-[13px] font-semibold text-on-accent transition-colors hover:bg-[#f0b878] lg:h-[38px]"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </Modal>
  );
}
