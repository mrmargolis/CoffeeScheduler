"use client";

import { useState, useRef, useCallback } from "react";

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
        className="px-4 py-2 bg-amber-700 text-white rounded-lg hover:bg-amber-800 transition-colors"
      >
        Import
      </button>
    );
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-gray-900 rounded-xl shadow-xl p-6 w-full max-w-md mx-4">
        <div className="flex justify-between items-center mb-4">
          <h2 className="text-lg font-semibold text-gray-300">
            Import BeanConqueror Export
          </h2>
          <button
            onClick={() => {
              setIsOpen(false);
              setResult(null);
            }}
            className="text-gray-500 hover:text-gray-300"
          >
            ✕
          </button>
        </div>

        <div
          onDragOver={(e) => {
            e.preventDefault();
            setIsDragging(true);
          }}
          onDragLeave={() => setIsDragging(false)}
          onDrop={handleDrop}
          className={`border-2 border-dashed rounded-lg p-8 text-center transition-colors ${
            isDragging
              ? "border-amber-500 bg-amber-950"
              : "border-gray-700 hover:border-gray-600"
          }`}
        >
          {isImporting ? (
            <p className="text-gray-400">Importing...</p>
          ) : (
            <>
              <p className="text-gray-400 mb-2">
                Drag & drop your .zip export here, or
              </p>
              <button
                onClick={() => fileInputRef.current?.click()}
                className="px-4 py-2 bg-amber-600 text-white rounded hover:bg-amber-700 transition-colors"
              >
                Choose File
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
            className={`mt-4 p-3 rounded-lg ${result.success ? "bg-green-950 text-green-300" : "bg-red-950 text-red-300"}`}
          >
            {result.success ? (
              <>
                <p className="font-medium">Import successful</p>
                <p className="text-sm mt-1">
                  {result.beansImported} beans, {result.brewsImported} brews
                  imported
                </p>
                {result.errors && result.errors.length > 0 && (
                  <details className="mt-2">
                    <summary className="text-sm cursor-pointer text-amber-400">
                      {result.errors.length} warnings
                    </summary>
                    <ul className="text-xs mt-1 space-y-1">
                      {result.errors.slice(0, 10).map((err, i) => (
                        <li key={i}>{err}</li>
                      ))}
                      {result.errors.length > 10 && (
                        <li>...and {result.errors.length - 10} more</li>
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
    </div>
  );
}
