import { describe, it, expect } from "vitest";
import {
  parseBCDate,
  isoToDate,
  dateToIso,
  addDays,
  daysBetween,
  dateRange,
} from "@/lib/date-utils";

describe("parseBCDate", () => {
  it("parses DD.MM.YYYY format", () => {
    expect(parseBCDate("15.01.2026")).toBe("2026-01-15");
    expect(parseBCDate("01.12.2025")).toBe("2025-12-01");
  });

  it("parses DD.MM.YYYY HH:MM:SS format", () => {
    expect(parseBCDate("22.02.2026 20:13:06")).toBe("2026-02-22");
  });

  it("parses single-digit day/month", () => {
    expect(parseBCDate("1.2.2026")).toBe("2026-02-01");
  });

  it('returns null for "Invalid date"', () => {
    expect(parseBCDate("Invalid date")).toBeNull();
  });

  it("returns null for empty string", () => {
    expect(parseBCDate("")).toBeNull();
  });

  it("returns null for garbage input", () => {
    expect(parseBCDate("not a date")).toBeNull();
  });

  it("returns null for invalid month/day", () => {
    expect(parseBCDate("32.13.2026")).toBeNull();
  });
});

describe("isoToDate", () => {
  it("converts ISO string to Date at midnight UTC", () => {
    const date = isoToDate("2026-01-15");
    expect(date.getUTCFullYear()).toBe(2026);
    expect(date.getUTCMonth()).toBe(0);
    expect(date.getUTCDate()).toBe(15);
    expect(date.getUTCHours()).toBe(0);
  });
});

describe("dateToIso", () => {
  it("converts Date to ISO string", () => {
    const date = new Date(Date.UTC(2026, 0, 15));
    expect(dateToIso(date)).toBe("2026-01-15");
  });
});

describe("addDays", () => {
  it("adds positive days", () => {
    expect(addDays("2026-01-15", 30)).toBe("2026-02-14");
  });

  it("adds negative days", () => {
    expect(addDays("2026-02-14", -30)).toBe("2026-01-15");
  });

  it("handles month boundaries", () => {
    expect(addDays("2026-01-31", 1)).toBe("2026-02-01");
  });

  it("handles year boundaries", () => {
    expect(addDays("2025-12-31", 1)).toBe("2026-01-01");
  });
});

describe("daysBetween", () => {
  it("returns positive difference", () => {
    expect(daysBetween("2026-01-01", "2026-02-01")).toBe(31);
  });

  it("returns negative difference", () => {
    expect(daysBetween("2026-02-01", "2026-01-01")).toBe(-31);
  });

  it("returns zero for same date", () => {
    expect(daysBetween("2026-01-15", "2026-01-15")).toBe(0);
  });
});

describe("dateRange", () => {
  it("generates inclusive range", () => {
    const range = dateRange("2026-01-01", "2026-01-03");
    expect(range).toEqual(["2026-01-01", "2026-01-02", "2026-01-03"]);
  });

  it("returns single date for same start/end", () => {
    const range = dateRange("2026-01-01", "2026-01-01");
    expect(range).toEqual(["2026-01-01"]);
  });

  it("returns empty array if end before start", () => {
    const range = dateRange("2026-01-03", "2026-01-01");
    expect(range).toEqual([]);
  });
});
