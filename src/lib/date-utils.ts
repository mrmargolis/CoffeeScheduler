/**
 * Parse DD.MM.YYYY or DD.MM.YYYY HH:MM:SS date strings to ISO 8601 (YYYY-MM-DD).
 * Returns null for invalid/unparseable dates.
 */
export function parseBCDate(dateStr: string): string | null {
  if (!dateStr || dateStr === "Invalid date") return null;

  // Match DD.MM.YYYY with optional HH:MM:SS
  const match = dateStr.match(
    /^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+\d{1,2}:\d{1,2}(?::\d{1,2})?)?$/
  );
  if (!match) return null;

  const day = parseInt(match[1], 10);
  const month = parseInt(match[2], 10);
  const year = parseInt(match[3], 10);

  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

/**
 * Convert ISO date string to Date object (at midnight UTC).
 */
export function isoToDate(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

/**
 * Convert a UTC Date to ISO 8601 date string (YYYY-MM-DD).
 * Only for use with dates created via isoToDate / Date.UTC.
 */
export function dateToIso(date: Date): string {
  return date.toISOString().split("T")[0];
}

/**
 * Format a Date as YYYY-MM-DD using local timezone.
 */
export function localDateStr(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * Add days to an ISO date string.
 */
export function addDays(iso: string, days: number): string {
  const date = isoToDate(iso);
  date.setUTCDate(date.getUTCDate() + days);
  return dateToIso(date);
}

/**
 * Difference in days between two ISO dates (end - start).
 */
export function daysBetween(startIso: string, endIso: string): number {
  const start = isoToDate(startIso);
  const end = isoToDate(endIso);
  return Math.round((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
}

/**
 * Get today's date as YYYY-MM-DD in local timezone.
 */
export function today(): string {
  return localDateStr(new Date());
}

/**
 * Generate array of ISO date strings from start to end (inclusive).
 */
export function dateRange(startIso: string, endIso: string): string[] {
  const dates: string[] = [];
  let current = startIso;
  while (current <= endIso) {
    dates.push(current);
    current = addDays(current, 1);
  }
  return dates;
}
