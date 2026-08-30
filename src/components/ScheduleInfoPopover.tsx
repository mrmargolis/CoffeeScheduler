"use client";

import { useState, useEffect, useRef } from "react";
import { InfoIcon } from "./icons";

export default function ScheduleInfoPopover() {
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;

    function handleClick(e: MouseEvent) {
      if (
        containerRef.current &&
        !containerRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    }

    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }

    document.addEventListener("mousedown", handleClick);
    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("mousedown", handleClick);
      document.removeEventListener("keydown", handleKey);
    };
  }, [open]);

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex h-[30px] w-[30px] items-center justify-center rounded-lg text-ink-faint transition-colors hover:bg-elevated hover:text-ink-muted"
        aria-label="How the schedule works"
      >
        <InfoIcon size={17} />
      </button>

      {open && (
        <div className="absolute right-0 top-full z-50 mt-2 w-96 rounded-xl border border-rule-strong bg-panel p-4 shadow-[0_24px_60px_rgba(0,0,0,0.6)]">
          <h3 className="mb-3 text-[13px] font-semibold">
            How the schedule works
          </h3>
          <ul className="flex flex-col gap-2 text-[12.5px] leading-[1.5] text-ink-muted">
            <Rule term="Queue order">
              Bags are scheduled by manual drag order → already started →
              earliest ready date. The order is followed strictly, so the next
              bag in the list is always the next bag in the schedule.
            </Rule>
            <Rule term="Early starts">
              If the next bag hasn&apos;t finished resting it is still
              scheduled, flagged on the calendar and in the backlog.
            </Rule>
            <Rule term="Ready date">
              Roast date + rest days + any time frozen. Frozen time pauses
              resting, it doesn&apos;t count toward it.
            </Rule>
            <Rule term="Rest days">
              Per-bag override → per-roaster default → global default.
            </Rule>
            <Rule term="Daily consumption">
              Up to your configured daily grams are projected per day.
            </Rule>
            <Rule term="Partial bags">
              Rounded to 15 g doses. Remnants under 12 g are discarded.
            </Rule>
            <Rule term="Frozen bags">
              Excluded from the schedule unless a thaw date is set.
            </Rule>
            <Rule term="Skip days">
              Click any date to toggle. No consumption is projected.
            </Rule>
            <Rule term="Gaps">
              Appear when no bag is available on a future day — every bag is
              either exhausted or still in the freezer.
            </Rule>
          </ul>
        </div>
      )}
    </div>
  );
}

function Rule({
  term,
  children,
}: {
  term: string;
  children: React.ReactNode;
}) {
  return (
    <li className="text-pretty">
      <strong className="font-semibold text-ink">{term}</strong> — {children}
    </li>
  );
}
