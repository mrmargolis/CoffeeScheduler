"use client";

import { useState, useEffect, useCallback } from "react";
import { mutate } from "swr";
import Calendar from "@/components/Calendar";
import BeanList from "@/components/BeanList";
import BeanDetail from "@/components/BeanDetail";
import ImportDialog from "@/components/ImportDialog";
import SettingsPanel from "@/components/SettingsPanel";
import RunwayStrip from "@/components/RunwayStrip";
import {
  BacklogIcon,
  BeanMark,
  CalendarIcon,
  PublishIcon,
  SettingsIcon,
} from "@/components/icons";

type MobileTab = "calendar" | "backlog";

export default function Home() {
  const [selectedBeanId, setSelectedBeanId] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [publishing, setPublishing] = useState(false);
  // Narrow screens show one pane at a time; wide screens show both.
  const [mobileTab, setMobileTab] = useState<MobileTab>("calendar");

  const handleEscape = useCallback((e: KeyboardEvent) => {
    if (e.key === "Escape") {
      setSelectedBeanId(null);
      setSettingsOpen(false);
    }
  }, []);

  useEffect(() => {
    document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, [handleEscape]);

  // Picking a bag anywhere pulls the backlog pane into view on a phone.
  const selectBean = useCallback((id: string) => {
    setSelectedBeanId(id);
    setMobileTab("backlog");
  }, []);

  const handlePublish = async () => {
    setPublishing(true);
    try {
      const res = await fetch("/api/publish", { method: "POST" });
      if (!res.ok) {
        const data = await res.json();
        alert(`Publish failed: ${data.details || "Unknown error"}`);
      }
    } catch (e) {
      alert(`Publish failed: ${e instanceof Error ? e.message : e}`);
    } finally {
      setPublishing(false);
    }
  };

  const handleImportComplete = () => {
    mutate("/api/beans");
    mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
      revalidate: true,
    });
  };

  return (
    <div className="min-h-screen pb-[72px] lg:pb-0">
      {/* Header */}
      <header className="border-b border-rule bg-panel px-4 lg:px-7">
        <div className="mx-auto flex h-[58px] max-w-screen-2xl items-center justify-between gap-6">
          <div className="flex items-center gap-2.5">
            <BeanMark size={19} className="text-accent" />
            <h1 className="text-[14.5px] font-semibold tracking-[-0.01em]">
              Coffee Scheduler
            </h1>
          </div>
          <div className="flex items-center gap-2">
            <ImportDialog onImportComplete={handleImportComplete} />
            <button
              onClick={handlePublish}
              disabled={publishing}
              className="flex h-[34px] items-center gap-[7px] rounded-lg border border-rule-strong px-3 text-[13px] text-ink-muted transition-colors hover:bg-elevated hover:text-ink disabled:cursor-not-allowed disabled:opacity-50"
            >
              <PublishIcon size={15} />
              <span className="hidden sm:inline">
                {publishing ? "Publishing…" : "Publish"}
              </span>
            </button>
            <button
              onClick={() => setSettingsOpen(true)}
              aria-label="Settings"
              className="flex h-[34px] w-[34px] items-center justify-center rounded-lg border border-rule-strong text-ink-muted transition-colors hover:bg-elevated hover:text-ink"
            >
              <SettingsIcon />
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-screen-2xl px-4 pt-4 lg:px-7 lg:pt-[22px]">
        <RunwayStrip onSelectBean={selectBean} />

        <div className="mt-4 flex flex-col gap-[22px] lg:mt-[22px] lg:flex-row lg:items-start">
          <div
            className={`min-w-0 flex-1 ${mobileTab === "calendar" ? "" : "hidden lg:block"}`}
          >
            <Calendar onSelectBean={selectBean} />
          </div>

          <aside
            className={`w-full shrink-0 overflow-hidden rounded-xl border border-rule bg-panel lg:w-[372px] ${
              mobileTab === "backlog" ? "" : "hidden lg:block"
            }`}
          >
            {selectedBeanId ? (
              <BeanDetail
                beanId={selectedBeanId}
                onClose={() => setSelectedBeanId(null)}
              />
            ) : (
              <BeanList
                onSelectBean={selectBean}
                selectedBeanId={selectedBeanId}
              />
            )}
          </aside>
        </div>
      </main>

      {/* Phone tab bar */}
      <nav className="fixed inset-x-0 bottom-0 z-40 grid grid-cols-2 border-t border-rule bg-panel lg:hidden">
        <TabButton
          active={mobileTab === "calendar"}
          onClick={() => setMobileTab("calendar")}
          icon={<CalendarIcon size={20} />}
          label="Calendar"
        />
        <TabButton
          active={mobileTab === "backlog"}
          onClick={() => setMobileTab("backlog")}
          icon={<BacklogIcon size={20} />}
          label="Backlog"
        />
      </nav>

      <SettingsPanel
        isOpen={settingsOpen}
        onClose={() => setSettingsOpen(false)}
      />
    </div>
  );
}

function TabButton({
  active,
  onClick,
  icon,
  label,
}: {
  active: boolean;
  onClick: () => void;
  icon: React.ReactNode;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      aria-current={active ? "page" : undefined}
      className={`flex h-16 flex-col items-center justify-center gap-1 transition-colors ${
        active ? "text-accent" : "text-ink-faint"
      }`}
    >
      {icon}
      <span className="text-[10.5px] font-medium">{label}</span>
    </button>
  );
}
