"use client";

import { useState, useEffect, useRef } from "react";

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
        className="text-gray-500 hover:text-gray-300 text-lg leading-none px-1"
        aria-label="Scheduling info"
      >
        &#9432;
      </button>

      {open && (
        <div className="absolute top-full left-0 mt-2 w-96 bg-gray-900 border border-gray-700 rounded-lg shadow-lg p-4 z-50 text-sm text-gray-300">
          <h3 className="text-gray-100 font-semibold mb-3">
            How the schedule works
          </h3>
          <ul className="space-y-2">
            <li>
              <strong className="text-gray-100">Queue order</strong> — Beans are
              scheduled by: manual drag order &rarr; already started &rarr;
              earliest ready date.
            </li>
            <li>
              <strong className="text-gray-100">Ready date</strong> — Roast date
              + rest days + any time frozen. Frozen time pauses resting, it
              doesn&apos;t count toward it.
            </li>
            <li>
              <strong className="text-gray-100">Rest days</strong> — Per-bean
              override &rarr; per-roaster default &rarr; global default (set in
              Settings).
            </li>
            <li>
              <strong className="text-gray-100">Daily consumption</strong> — Up
              to your configured daily grams (default 45&nbsp;g) are projected
              per day.
            </li>
            <li>
              <strong className="text-gray-100">Partial beans</strong> — Rounded
              to 15&nbsp;g doses. Remnants under 12&nbsp;g are discarded.
            </li>
            <li>
              <strong className="text-gray-100">Frozen beans</strong> — Excluded
              from the schedule unless a thaw date is set.
            </li>
            <li>
              <strong className="text-gray-100">Skip days</strong> — Click any
              date to toggle. No consumption is projected on skip days.
            </li>
            <li>
              <strong className="text-gray-100">Gaps</strong> — Appear when no
              beans are ready on a future day.
            </li>
          </ul>
        </div>
      )}
    </div>
  );
}
