"use client";

import { useState, useRef, useCallback } from "react";
import Modal from "./Modal";
import { ImportIcon } from "./icons";

interface ImportResult {
  success: boolean;
  beansImported?: number;
  brewsImported?: number;
  errors?: string[];
  error?: string;
}

export default function ImportDialog({
  onImportComplete,
}: {
  onImportComplete?: () => void;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const [isDragging, setIsDragging] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [result, setResult] = useState<ImportResult | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleImport = useCallback(
    async (file: File) => {
      setIsImporting(true);
      setResult(null);

      const formData = new FormData();
      formData.append("file", file);

      try {
        const res = await fetch("/api/import", {
          method: "POST",
          body: formData,
        });
        const data = await res.json();
        setResult(data);
        if (data.success) {
          onImportComplete?.();
        }
      } catch {
        setResult({ success: false, error: "Failed to upload file" });
      } finally {
        setIsImporting(false);
      }
    },
    [onImportComplete]
  );

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragging(false);
      const file = e.dataTransfer.files[0];
      if (file && file.name.endsWith(".zip")) {
        handleImport(file);
      }
    },
    [handleImport]
  );

  const handleFileSelect = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) {
        handleImport(file);
      }
    },
    [handleImport]
  );

  if (!isOpen) {
    return (
      <button
        onClick={() => setIsOpen(true)}
        className="flex h-[34px] items-center gap-[7px] rounded-lg border border-rule-strong px-3 text-[13px] text-ink-muted transition-colors hover:bg-elevated hover:text-ink"
      >
        <ImportIcon size={15} />
        <span className="hidden sm:inline">Import</span>
      </button>
    );
  }

  const close = () => {
    setIsOpen(false);
    setResult(null);
  };

  return (
    <Modal
      title="Import BeanConqueror export"
      onClose={close}
      widthClass="max-w-md"
    >
      <div className="px-[18px] pb-[18px] pt-4">
        <div
          onDragOver={(e) => {
            e.preventDefault();
            setIsDragging(true);
          }}
          onDragLeave={() => setIsDragging(false)}
          onDrop={handleDrop}
          className={`rounded-[10px] border border-dashed p-8 text-center transition-colors ${
            isDragging
              ? "border-accent bg-accent-wash"
              : "border-rule-strong hover:border-ink-faint"
          }`}
        >
          {isImporting ? (
            <p className="text-[13px] text-ink-muted">Importing…</p>
          ) : (
            <>
              <p className="mb-3 text-[13px] text-ink-muted">
                Drop your .zip export here, or
              </p>
              <button
                onClick={() => fileInputRef.current?.click()}
                className="h-[38px] rounded-[9px] bg-accent px-4 text-[13px] font-semibold text-on-accent transition-colors hover:bg-[#f0b878]"
              >
                Choose file
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept=".zip"
                onChange={handleFileSelect}
                className="hidden"
              />
            </>
          )}
        </div>

        {result && (
          <div
            className={`mt-4 rounded-[10px] p-3 text-[12.5px] ${
              result.success
                ? "bg-ok-wash text-ok"
                : "bg-alert-wash text-alert"
            }`}
          >
            {result.success ? (
              <>
                <p className="font-medium">Import successful</p>
                <p className="mt-1 font-mono tabular-nums">
                  {result.beansImported} bags, {result.brewsImported} brews
                </p>
                {result.errors && result.errors.length > 0 && (
                  <details className="mt-2">
                    <summary className="cursor-pointer text-accent">
                      {result.errors.length} warnings
                    </summary>
                    <ul className="mt-1.5 flex flex-col gap-1 text-[11.5px] text-ink-muted">
                      {result.errors.slice(0, 10).map((err, i) => (
                        <li key={i}>{err}</li>
                      ))}
                      {result.errors.length > 10 && (
                        <li>…and {result.errors.length - 10} more</li>
                      )}
                    </ul>
                  </details>
                )}
              </>
            ) : (
              <p>{result.error}</p>
            )}
          </div>
        )}
      </div>
    </Modal>
  );
}
