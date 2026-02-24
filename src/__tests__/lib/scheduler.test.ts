import { describe, it, expect } from "vitest";
import {
  computeSchedule,
  computeReadyDate,
  sortBeanQueue,
  SchedulerBean,
} from "@/lib/scheduler";

function makeBean(overrides: Partial<SchedulerBean> = {}): SchedulerBean {
  return {
    id: "bean-1",
    name: "Test Bean",
    roaster: "Test Roaster",
    roast_date: "2026-01-01",
    weight_grams: 250,
    remaining_grams: 250,
    effective_rest_days: 30,
    is_frozen: false,
    planned_thaw_date: null,
    display_order: null,
    frozen_days: 0,
    ...overrides,
  };
}

describe("computeReadyDate", () => {
  it("computes ready date from roast date + rest days", () => {
    const bean = makeBean({ roast_date: "2026-01-01", effective_rest_days: 30 });
    expect(computeReadyDate(bean)).toBe("2026-01-31");
  });

  it("accounts for frozen days", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      frozen_days: 10,
    });
    expect(computeReadyDate(bean)).toBe("2026-02-10");
  });

  it("returns null for beans with no roast date", () => {
    const bean = makeBean({ roast_date: null });
    expect(computeReadyDate(bean)).toBeNull();
  });
});

describe("sortBeanQueue", () => {
  it("puts display_order beans first, sorted by order", () => {
    const beans = [
      makeBean({ id: "b1", display_order: 3 }),
      makeBean({ id: "b2", display_order: 1 }),
      makeBean({ id: "b3", display_order: null, roast_date: "2026-01-01" }),
    ];
    const sorted = sortBeanQueue(beans);
    expect(sorted.map((b) => b.id)).toEqual(["b2", "b1", "b3"]);
  });

  it("sorts unordered beans by ready date", () => {
    const beans = [
      makeBean({
        id: "b1",
        roast_date: "2026-02-01",
        effective_rest_days: 30,
      }),
      makeBean({
        id: "b2",
        roast_date: "2026-01-01",
        effective_rest_days: 30,
      }),
    ];
    const sorted = sortBeanQueue(beans);
    expect(sorted[0].id).toBe("b2");
  });

  it("puts in-progress beans before untouched beans", () => {
    const beans = [
      makeBean({
        id: "untouched",
        roast_date: "2026-01-01",
        effective_rest_days: 30,
        weight_grams: 200,
        remaining_grams: 200,
      }),
      makeBean({
        id: "in-progress",
        roast_date: "2026-01-10",
        effective_rest_days: 30,
        weight_grams: 200,
        remaining_grams: 50,
      }),
    ];
    const sorted = sortBeanQueue(beans);
    expect(sorted[0].id).toBe("in-progress");
    expect(sorted[1].id).toBe("untouched");
  });

  it("puts beans with no ready date last", () => {
    const beans = [
      makeBean({ id: "b1", roast_date: null }),
      makeBean({ id: "b2", roast_date: "2026-01-01" }),
    ];
    const sorted = sortBeanQueue(beans);
    expect(sorted[0].id).toBe("b2");
    expect(sorted[1].id).toBe("b1");
  });
});

describe("computeSchedule", () => {
  it("consumes a single bag over time", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 90, // 2 days at 45g (depletes to 0, below 12g min dose)
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-02",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01", // Before range, so all projected
    });

    expect(schedule).toHaveLength(3);
    // Day 1: 45g consumed
    expect(schedule[0].consumptions[0].grams).toBe(45);
    expect(schedule[0].is_gap).toBe(false);
    // Day 2: 45g consumed (depletes the bag)
    expect(schedule[1].consumptions[0].grams).toBe(45);
    // Day 3: no coffee left → gap
    expect(schedule[2].is_gap).toBe(true);
    expect(schedule[2].consumptions).toHaveLength(0);
  });

  it("transitions between bags when one runs out", () => {
    const bean1 = makeBean({
      id: "b1",
      name: "Bean 1",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 30, // Above 12g min dose, all 30g usable
      weight_grams: 200,
    });
    const bean2 = makeBean({
      id: "b2",
      name: "Bean 2",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 45,
      beans: [bean1, bean2],
      actualBrews: [],
      today: "2026-01-01",
    });

    expect(schedule[0].consumptions).toHaveLength(2);
    expect(schedule[0].consumptions[0]).toEqual({
      bean_id: "b1",
      bean_name: "Bean 1",
      roaster: "Test Roaster",
      grams: 30,
    });
    expect(schedule[0].consumptions[1]).toEqual({
      bean_id: "b2",
      bean_name: "Bean 2",
      roaster: "Test Roaster",
      grams: 15,
    });
  });

  it("rounds partial bean to dose multiples and fills remainder from next bean", () => {
    const bean1 = makeBean({
      id: "b1",
      name: "Bean 1",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 40, // 40g → 2 doses (30g), 10g wasted
      weight_grams: 200,
    });
    const bean2 = makeBean({
      id: "b2",
      name: "Bean 2",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 45,
      beans: [bean1, bean2],
      actualBrews: [],
      today: "2026-01-01",
    });

    // Bean1: 30g (2 × 15g doses, 10g wasted), Bean2: 15g (1 dose)
    expect(schedule[0].consumptions).toHaveLength(2);
    expect(schedule[0].consumptions[0].bean_id).toBe("b1");
    expect(schedule[0].consumptions[0].grams).toBe(30);
    expect(schedule[0].consumptions[1].bean_id).toBe("b2");
    expect(schedule[0].consumptions[1].grams).toBe(15);
  });

  it("does not start a second bean when shortfall is below minimum dose", () => {
    const bean1 = makeBean({
      id: "b1",
      name: "Bean 1",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });
    const bean2 = makeBean({
      id: "b2",
      name: "Bean 2",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 50, // 50g target, bean1 fills it. 5g gap if bean1 had 45g.
      beans: [bean1, bean2],
      actualBrews: [],
      today: "2026-01-01",
    });

    // Bean1 fills the full target, no need for bean2
    expect(schedule[0].consumptions).toHaveLength(1);
    expect(schedule[0].consumptions[0].bean_id).toBe("b1");
    expect(schedule[0].consumptions[0].grams).toBe(50);
  });

  it("respects bean queue order (display_order)", () => {
    const bean1 = makeBean({
      id: "b1",
      name: "Bean 1",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      display_order: 2,
      remaining_grams: 250,
    });
    const bean2 = makeBean({
      id: "b2",
      name: "Bean 2",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      display_order: 1,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 45,
      beans: [bean1, bean2],
      actualBrews: [],
      today: "2026-01-01",
    });

    // bean2 (display_order=1) should be consumed first
    expect(schedule[0].consumptions[0].bean_id).toBe("b2");
  });

  it("detects gap days when no coffee available", () => {
    // Bean not ready until Feb 14
    const bean = makeBean({
      roast_date: "2026-01-15",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-02-13",
      endDate: "2026-02-15",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
    });

    expect(schedule[0].is_gap).toBe(true); // Feb 13: not ready
    expect(schedule[1].is_gap).toBe(false); // Feb 14: ready
    expect(schedule[2].is_gap).toBe(false); // Feb 15: still has coffee
  });

  it("detects surplus when multiple bags ready", () => {
    const bean1 = makeBean({
      id: "b1",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });
    const bean2 = makeBean({
      id: "b2",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 45,
      beans: [bean1, bean2],
      actualBrews: [],
      today: "2026-01-01",
    });

    expect(schedule[0].is_surplus).toBe(true);
  });

  it("freeze/thaw adjusts ready dates via frozen_days", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      frozen_days: 15,
      remaining_grams: 250,
    });

    // Ready date should be Jan 1 + 30 + 15 = Feb 15
    const schedule = computeSchedule({
      startDate: "2026-02-14",
      endDate: "2026-02-16",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
    });

    expect(schedule[0].is_gap).toBe(true); // Feb 14: not ready
    expect(schedule[1].is_gap).toBe(false); // Feb 15: ready
  });

  it("uses actual brew data for past days", () => {
    const bean = makeBean({
      id: "b1",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-02-01",
      endDate: "2026-02-03",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [
        {
          bean_id: "b1",
          creation_date: "2026-02-01",
          ground_coffee_grams: 15,
        },
        {
          bean_id: "b1",
          creation_date: "2026-02-01",
          ground_coffee_grams: 15,
        },
      ],
      today: "2026-02-02",
    });

    // Feb 1: actual brews (past) — same bean aggregated into one consumption
    expect(schedule[0].is_actual).toBe(true);
    expect(schedule[0].consumptions).toHaveLength(1);
    expect(schedule[0].consumptions[0].grams).toBe(30);

    // Feb 2: today with no brews → projected
    expect(schedule[1].is_actual).toBe(false);

    // remaining_grams already accounts for past brews, so projected from 250
    expect(schedule[1].consumptions[0].grams).toBe(45);
  });

  it("past days with no brews show as gaps", () => {
    const bean = makeBean({ remaining_grams: 250 });

    const schedule = computeSchedule({
      startDate: "2026-02-01",
      endDate: "2026-02-01",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-02-15",
    });

    expect(schedule[0].is_actual).toBe(true);
    expect(schedule[0].is_gap).toBe(true);
  });

  it("excludes frozen beans from schedule", () => {
    const bean = makeBean({
      is_frozen: true,
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
    });

    expect(schedule[0].is_gap).toBe(true);
  });

  it("includes frozen bean with planned_thaw_date in schedule", () => {
    const bean = makeBean({
      is_frozen: true,
      planned_thaw_date: "2026-02-10",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      frozen_days: 40, // freeze start to planned thaw
      remaining_grams: 250,
    });

    // Ready date = Jan 1 + 30 + 40 = Mar 12
    const schedule = computeSchedule({
      startDate: "2026-03-12",
      endDate: "2026-03-12",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-02-01",
    });

    expect(schedule[0].is_gap).toBe(false);
    expect(schedule[0].consumptions[0].grams).toBe(45);
  });

  it("excludes frozen bean without planned_thaw_date from schedule", () => {
    const bean = makeBean({
      is_frozen: true,
      planned_thaw_date: null,
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-03-01",
      endDate: "2026-03-01",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-02-01",
    });

    expect(schedule[0].is_gap).toBe(true);
  });

  it("ready date accounts for projected frozen_days through thaw date", () => {
    // Bean roasted Jan 1, rest 30d, frozen for 20 days (projected to thaw date)
    const bean = makeBean({
      is_frozen: true,
      planned_thaw_date: "2026-02-15",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      frozen_days: 20,
      remaining_grams: 250,
    });

    // Ready date = Jan 1 + 30 + 20 = Feb 20
    const schedule = computeSchedule({
      startDate: "2026-02-19",
      endDate: "2026-02-21",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-26",
    });

    expect(schedule[0].is_gap).toBe(true); // Feb 19: not ready
    expect(schedule[1].is_gap).toBe(false); // Feb 20: ready
    expect(schedule[2].is_gap).toBe(false); // Feb 21: still has coffee
  });

  it("excludes beans at or below minimum dose (12g)", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 12, // At threshold → treated as done
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
    });

    expect(schedule[0].consumptions).toHaveLength(0);
    expect(schedule[0].is_gap).toBe(true);
  });

  it("tosses remnant and shows gap when below acceptable minimum (39g)", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 30, // Only 30g available, below 39g minimum
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-01",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
    });

    // 30g < 39g acceptable minimum → remnant tossed, day is a gap
    expect(schedule[0].consumptions).toHaveLength(0);
    expect(schedule[0].is_gap).toBe(true);
    // Next day: bean was wasted, still a gap
    expect(schedule[1].is_gap).toBe(true);
  });

  it("does not mark gap when total consumption meets acceptable minimum (39g)", () => {
    // Bean1 has 24g → 1 dose (15g), 9g waste. Bean2 fills remaining 30g.
    // Total = 45g, well above minimum.
    const bean1 = makeBean({
      id: "b1",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 24,
      weight_grams: 200,
    });
    const bean2 = makeBean({
      id: "b2",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 45,
      beans: [bean1, bean2],
      actualBrews: [],
      today: "2026-01-01",
    });

    expect(schedule[0].consumptions).toHaveLength(2);
    expect(schedule[0].consumptions[0].grams).toBe(15); // 1 dose from bean1
    expect(schedule[0].consumptions[1].grams).toBe(30); // 2 doses from bean2
    expect(schedule[0].is_gap).toBe(false);
  });

  it("single bean covering full target is not dose-rounded", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
    });

    // Full target consumed, no rounding needed
    expect(schedule[0].consumptions[0].grams).toBe(45);
    expect(schedule[0].is_gap).toBe(false);
  });

  it("single skip day shifts consumption forward by 1 day", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 135, // 3 days at 45g
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-04",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
      skipDays: new Set(["2026-02-01"]),
    });

    // Jan 31: consume 45g
    expect(schedule[0].consumptions[0].grams).toBe(45);
    expect(schedule[0].is_skip).toBe(false);
    // Feb 1: skip day
    expect(schedule[1].is_skip).toBe(true);
    expect(schedule[1].consumptions).toHaveLength(0);
    // Feb 2: consume 45g (shifted forward)
    expect(schedule[2].consumptions[0].grams).toBe(45);
    // Feb 3: consume 45g (shifted forward)
    expect(schedule[3].consumptions[0].grams).toBe(45);
    // Feb 4: out of coffee
    expect(schedule[4].is_gap).toBe(true);
  });

  it("multi-day skip range pushes consumption forward", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 90, // 2 days at 45g
    });

    const skipDays = new Set(["2026-01-31", "2026-02-01", "2026-02-02"]);

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-04",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
      skipDays,
    });

    // First 3 days are skips
    expect(schedule[0].is_skip).toBe(true);
    expect(schedule[1].is_skip).toBe(true);
    expect(schedule[2].is_skip).toBe(true);
    // Feb 3: consume
    expect(schedule[3].consumptions[0].grams).toBe(45);
    // Feb 4: consume
    expect(schedule[4].consumptions[0].grams).toBe(45);
  });

  it("skip day doesn't deduct remaining grams", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 90,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-03",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
      skipDays: new Set(["2026-02-01"]),
    });

    // Total consumption across range should still be 90g
    const totalConsumed = schedule.reduce(
      (sum, day) => sum + day.consumptions.reduce((s, c) => s + c.grams, 0),
      0
    );
    expect(totalConsumed).toBe(90);
  });

  it("skip day is not a gap", () => {
    const bean = makeBean({
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 90,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-01-31",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [],
      today: "2026-01-01",
      skipDays: new Set(["2026-01-31"]),
    });

    expect(schedule[0].is_skip).toBe(true);
    expect(schedule[0].is_gap).toBe(false);
  });

  it("skip days interact with bag transitions", () => {
    const bean1 = makeBean({
      id: "b1",
      name: "Bean 1",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 45, // Exactly 1 day
    });
    const bean2 = makeBean({
      id: "b2",
      name: "Bean 2",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-01-31",
      endDate: "2026-02-03",
      dailyConsumptionGrams: 45,
      beans: [bean1, bean2],
      actualBrews: [],
      today: "2026-01-01",
      skipDays: new Set(["2026-02-01"]),
    });

    // Jan 31: consume bean1 (depletes it)
    expect(schedule[0].consumptions[0].bean_id).toBe("b1");
    // Feb 1: skip
    expect(schedule[1].is_skip).toBe(true);
    // Feb 2: consume bean2 (bean1 exhausted)
    expect(schedule[2].consumptions[0].bean_id).toBe("b2");
  });

  it("past skip days with actual brews override skip", () => {
    const bean = makeBean({
      id: "b1",
      roast_date: "2026-01-01",
      effective_rest_days: 30,
      remaining_grams: 250,
    });

    const schedule = computeSchedule({
      startDate: "2026-02-01",
      endDate: "2026-02-02",
      dailyConsumptionGrams: 45,
      beans: [bean],
      actualBrews: [
        {
          bean_id: "b1",
          creation_date: "2026-02-01",
          ground_coffee_grams: 15,
        },
      ],
      today: "2026-02-15",
      skipDays: new Set(["2026-02-01"]),
    });

    // Past day with actual brew: override skip
    expect(schedule[0].is_actual).toBe(true);
    expect(schedule[0].is_skip).toBe(false);
    expect(schedule[0].consumptions[0].grams).toBe(15);
  });
});
