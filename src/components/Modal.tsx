"use client";

import { CloseIcon } from "./icons";

/** Shared shell for the app's dialogs: scrim, card, titled header. */
export default function Modal({
  title,
  subtitle,
  onClose,
  widthClass = "max-w-sm",
  children,
}: {
  title: string;
  subtitle?: string;
  onClose: () => void;
  widthClass?: string;
  children: React.ReactNode;
}) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-0 sm:items-center sm:p-4"
      onClick={onClose}
    >
      <div
        className={`max-h-[92vh] w-full overflow-y-auto rounded-t-2xl border border-rule-strong bg-panel shadow-[0_24px_60px_rgba(0,0,0,0.6)] sm:rounded-[14px] ${widthClass}`}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sticky top-0 flex items-center justify-between gap-3 border-b border-rule bg-panel px-[18px] py-[15px]">
          <div className="min-w-0">
            <h2 className="text-[15.5px] font-semibold tracking-[-0.012em]">
              {title}
            </h2>
            {subtitle && (
              <p className="font-mono text-[11.5px] tabular-nums text-ink-faint">
                {subtitle}
              </p>
            )}
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="-mr-1.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-ink-faint transition-colors hover:bg-elevated hover:text-ink"
          >
            <CloseIcon size={15} />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
