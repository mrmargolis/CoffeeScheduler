"use client";

import { useState, useEffect, useCallback } from "react";
import { mutate } from "swr";
import Calendar from "@/components/Calendar";
import BeanList from "@/components/BeanList";
import BeanDetail from "@/components/BeanDetail";
import ImportDialog from "@/components/ImportDialog";
import SettingsPanel from "@/components/SettingsPanel";

export default function Home() {
  const [selectedBeanId, setSelectedBeanId] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);

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

  const handleImportComplete = () => {
    mutate("/api/beans");
    mutate((key: string) => key?.startsWith("/api/schedule"), undefined, {
      revalidate: true,
    });
  };

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="bg-gray-900 border-b border-gray-700 px-6 py-3">
        <div className="flex items-center justify-between max-w-screen-2xl mx-auto">
          <h1 className="text-xl font-semibold text-gray-300">
            CoffeeScheduler
          </h1>
          <div className="flex items-center gap-3">
            <ImportDialog onImportComplete={handleImportComplete} />
            <button
              onClick={() => setSettingsOpen(true)}
              className="px-4 py-2 text-gray-400 hover:text-gray-200 border border-gray-700 rounded-lg hover:bg-gray-800 transition-colors"
            >
              Settings
            </button>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <div className="max-w-screen-2xl mx-auto px-6 py-6">
        <div className="flex gap-6">
          {/* Calendar */}
          <div className="flex-1 min-w-0">
            <Calendar onSelectBean={setSelectedBeanId} />
          </div>

          {/* Sidebar */}
          <div className="w-80 shrink-0">
            <div className="bg-gray-900 rounded-xl shadow-sm border border-gray-700 overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-700">
                <h2 className="font-semibold text-gray-300 text-sm">
                  Bean Queue
                </h2>
              </div>
              {selectedBeanId ? (
                <BeanDetail
                  beanId={selectedBeanId}
                  onClose={() => setSelectedBeanId(null)}
                />
              ) : (
                <BeanList
                  onSelectBean={setSelectedBeanId}
                  selectedBeanId={selectedBeanId}
                />
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Settings Modal */}
      <SettingsPanel
        isOpen={settingsOpen}
        onClose={() => setSettingsOpen(false)}
      />
    </div>
  );
}
