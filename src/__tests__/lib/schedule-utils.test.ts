import { describe, it, expect } from "vitest";
import { extractBeanFinishDates, extractBeanStartDates } from "@/lib/schedule-utils";
import { ScheduleDay } from "@/lib/types";

function makeDay(
  date: string,
  consumptions: { bean_id: string }[]
): ScheduleDay {
  return {
    date,
    consumptions: consumptions.map((c) => ({
      ...c,
      bean_name: "Test",
      roaster: "Test",
      grams: 18,
    })),
    is_gap: false,
    is_surplus: false,
    is_actual: false,
    is_skip: false,
  };
}

describe("extractBeanFinishDates", () => {
  it("returns the last date a bean appears in the schedule", () => {
    const schedule = [
      makeDay("2025-01-01", [{ bean_id: "a" }]),
      makeDay("2025-01-02", [{ bean_id: "a" }]),
      makeDay("2025-01-03", [{ bean_id: "a" }]),
    ];
    const result = extractBeanFinishDates(schedule);
    expect(result.get("a")).toBe("2025-01-03");
  });

  it("returns correct finish dates for multiple beans", () => {
    const schedule = [
      makeDay("2025-01-01", [{ bean_id: "a" }]),
      makeDay("2025-01-02", [{ bean_id: "a" }, { bean_id: "b" }]),
      makeDay("2025-01-03", [{ bean_id: "b" }]),
      makeDay("2025-01-04", [{ bean_id: "c" }]),
    ];
    const result = extractBeanFinishDates(schedule);
    expect(result.get("a")).toBe("2025-01-02");
    expect(result.get("b")).toBe("2025-01-03");
    expect(result.get("c")).toBe("2025-01-04");
  });

  it("returns an empty map for an empty schedule", () => {
    const result = extractBeanFinishDates([]);
    expect(result.size).toBe(0);
  });
});

describe("extractBeanStartDates", () => {
  it("returns the first date a bean appears in the schedule", () => {
    const schedule = [
      makeDay("2025-01-01", [{ bean_id: "a" }]),
      makeDay("2025-01-02", [{ bean_id: "a" }]),
      makeDay("2025-01-03", [{ bean_id: "a" }]),
    ];
    const result = extractBeanStartDates(schedule);
    expect(result.get("a")).toBe("2025-01-01");
  });

  it("returns correct start dates for multiple beans", () => {
    const schedule = [
      makeDay("2025-01-01", [{ bean_id: "a" }]),
      makeDay("2025-01-02", [{ bean_id: "a" }, { bean_id: "b" }]),
      makeDay("2025-01-03", [{ bean_id: "b" }]),
      makeDay("2025-01-04", [{ bean_id: "c" }]),
    ];
    const result = extractBeanStartDates(schedule);
    expect(result.get("a")).toBe("2025-01-01");
    expect(result.get("b")).toBe("2025-01-02");
    expect(result.get("c")).toBe("2025-01-04");
  });

  it("returns an empty map for an empty schedule", () => {
    const result = extractBeanStartDates([]);
    expect(result.size).toBe(0);
  });
});
