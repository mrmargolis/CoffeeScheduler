import { describe, it, expect } from "vitest";
import { buildCalendarEvents } from "@/lib/calendar-utils";
import { ScheduleDay, SkipDayRange } from "@/lib/types";

function makeDay(overrides: Partial<ScheduleDay> & { date: string }): ScheduleDay {
  return {
    consumptions: [],
    is_gap: false,
    is_surplus: false,
    is_actual: false,
    is_skip: false,
    ...overrides,
  };
}

describe("buildCalendarEvents", () => {
  const today = "2026-02-25";

  it("returns empty events and null summary for null schedule", () => {
    const result = buildCalendarEvents(null, undefined, today);
    expect(result.events).toEqual([]);
    expect(result.summary).toBeNull();
  });

  it("returns empty events and summary for empty schedule", () => {
    const result = buildCalendarEvents([], undefined, today);
    expect(result.events).toEqual([]);
    expect(result.summary).toEqual({ daysOfCoffee: 0, nextGapDate: null });
  });

  it("merges consecutive single-bean days into one span event", () => {
    const schedule: ScheduleDay[] = [
      makeDay({
        date: "2026-03-01",
        consumptions: [{ bean_id: "b1", bean_name: "Ethiopia", roaster: "SM", grams: 45 }],
      }),
      makeDay({
        date: "2026-03-02",
        consumptions: [{ bean_id: "b1", bean_name: "Ethiopia", roaster: "SM", grams: 45 }],
      }),
      makeDay({
        date: "2026-03-03",
        consumptions: [{ bean_id: "b1", bean_name: "Ethiopia", roaster: "SM", grams: 45 }],
      }),
    ];

    const { events } = buildCalendarEvents(schedule, undefined, today);

    // Should produce one merged event
    const beanEvents = events.filter((e) => e.extendedProps?.beanId === "b1");
    expect(beanEvents).toHaveLength(1);
    expect(beanEvents[0].start).toBe("2026-03-01");
    expect(beanEvents[0].end).toBe("2026-03-04"); // exclusive end
    expect(beanEvents[0].title).toBe("135g · Ethiopia");
  });

  it("breaks spans at skip days", () => {
    const schedule: ScheduleDay[] = [
      makeDay({
        date: "2026-03-01",
        consumptions: [{ bean_id: "b1", bean_name: "Ethiopia", roaster: "SM", grams: 45 }],
      }),
      makeDay({ date: "2026-03-02", is_skip: true }),
      makeDay({
        date: "2026-03-03",
        consumptions: [{ bean_id: "b1", bean_name: "Ethiopia", roaster: "SM", grams: 45 }],
      }),
    ];

    const skipRanges: SkipDayRange[] = [
      { start_date: "2026-03-02", end_date: "2026-03-02", reason: "Travel" },
    ];

    const { events } = buildCalendarEvents(schedule, skipRanges, today);

    const beanEvents = events.filter((e) => e.extendedProps?.beanId === "b1");
    expect(beanEvents).toHaveLength(2);

    const skipEvents = events.filter((e) => e.classNames?.includes("skip-day"));
    expect(skipEvents).toHaveLength(1);
    expect(skipEvents[0].title).toBe("Travel");
  });

  it("produces gap day events", () => {
    const schedule: ScheduleDay[] = [
      makeDay({ date: "2026-03-01", is_gap: true }),
    ];

    const { events } = buildCalendarEvents(schedule, undefined, today);

    const gapEvents = events.filter((e) => e.classNames?.includes("gap-day"));
    expect(gapEvents).toHaveLength(1);
    expect(gapEvents[0].title).toBe("No coffee!");
  });

  it("flushes spans and creates individual events for multi-bean days", () => {
    const schedule: ScheduleDay[] = [
      makeDay({
        date: "2026-03-01",
        consumptions: [{ bean_id: "b1", bean_name: "Ethiopia", roaster: "SM", grams: 45 }],
      }),
      makeDay({
        date: "2026-03-02",
        consumptions: [
          { bean_id: "b1", bean_name: "Ethiopia", roaster: "SM", grams: 30 },
          { bean_id: "b2", bean_name: "Colombia", roaster: "TW", grams: 15 },
        ],
      }),
    ];

    const { events } = buildCalendarEvents(schedule, undefined, today);

    // First day's span gets flushed, then two individual events for day 2
    const beanEvents = events.filter((e) => e.extendedProps);
    expect(beanEvents).toHaveLength(3);
  });

  it("computes summary with daysOfCoffee and nextGapDate", () => {
    const schedule: ScheduleDay[] = [
      makeDay({
        date: "2026-03-01",
        consumptions: [{ bean_id: "b1", bean_name: "Ethiopia", roaster: "SM", grams: 45 }],
      }),
      makeDay({
        date: "2026-03-02",
        consumptions: [{ bean_id: "b1", bean_name: "Ethiopia", roaster: "SM", grams: 45 }],
      }),
      makeDay({ date: "2026-03-03", is_gap: true }),
      makeDay({ date: "2026-03-04", is_skip: true }),
    ];

    const { summary } = buildCalendarEvents(schedule, undefined, today);

    expect(summary).not.toBeNull();
    expect(summary!.daysOfCoffee).toBe(2);
    expect(summary!.nextGapDate).toBe("2026-03-03");
  });

  it("skip events show reason from SkipDayRange", () => {
    const schedule: ScheduleDay[] = [
      makeDay({ date: "2026-03-02", is_skip: true }),
    ];

    const skipRanges: SkipDayRange[] = [
      { start_date: "2026-03-02", end_date: "2026-03-02", reason: "Vacation" },
    ];

    const { events } = buildCalendarEvents(schedule, skipRanges, today);

    const skipEvents = events.filter((e) => e.classNames?.includes("skip-day"));
    expect(skipEvents[0].title).toBe("Vacation");
  });

  it("uses default 'Skip' when no reason provided", () => {
    const schedule: ScheduleDay[] = [
      makeDay({ date: "2026-03-02", is_skip: true }),
    ];

    const skipRanges: SkipDayRange[] = [
      { start_date: "2026-03-02", end_date: "2026-03-02" },
    ];

    const { events } = buildCalendarEvents(schedule, skipRanges, today);

    const skipEvents = events.filter((e) => e.classNames?.includes("skip-day"));
    expect(skipEvents[0].title).toBe("Skip");
  });
});
