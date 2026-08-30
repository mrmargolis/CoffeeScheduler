import { describe, it, expect, afterEach, vi } from "vitest";
import {
  DayCellData,
  collectBagRuns,
  renderBagList,
  renderDayCell,
  REHIGHLIGHT_SCRIPT,
} from "@/lib/schedule-html";
import { ScheduleDay } from "@/lib/types";

function makeCell(overrides: Partial<DayCellData> = {}): DayCellData {
  return {
    date: "2026-06-21",
    dayNum: 21,
    isToday: false,
    isGap: false,
    isSkip: false,
    consumptions: [],
    ...overrides,
  };
}

describe("renderDayCell", () => {
  it("includes a data-date attribute with the cell's ISO date", () => {
    const html = renderDayCell(makeCell({ date: "2026-06-21" }));
    expect(html).toContain('data-date="2026-06-21"');
  });

  it("bakes in the today class when isToday is set", () => {
    const html = renderDayCell(makeCell({ isToday: true }));
    expect(html).toContain("today");
  });

  it("renders empty cells without a data-date", () => {
    const html = renderDayCell(null);
    expect(html).toBe('<div class="cell empty"></div>');
  });
  it("renders a colour stripe per bag rather than a text pill", () => {
    const html = renderDayCell(
      makeCell({
        consumptions: [
          { bean_id: "b1", bean_name: "Ethiopia Guji", roaster: "Square Mile", grams: 45 },
        ],
      })
    );
    // The grid carries colour only; the name lives in the tap-through detail.
    expect(html).toContain('class="stripe"');
    expect(html).not.toContain(">Ethiopia Guji<");
    expect(html).toContain("Ethiopia Guji"); // inside the escaped data-detail
  });

  it("marks gap and skip days with their own stripes", () => {
    expect(renderDayCell(makeCell({ isGap: true }))).toContain("gap-stripe");
    expect(renderDayCell(makeCell({ isSkip: true }))).toContain("skip-stripe");
  });

  it("omits data-detail on a day with nothing on it", () => {
    expect(renderDayCell(makeCell())).not.toContain("data-detail");
  });
});

function makeDay(date: string, cs: ScheduleDay["consumptions"]): ScheduleDay {
  return {
    date,
    consumptions: cs,
    is_gap: false,
    is_surplus: false,
    is_actual: false,
    is_skip: false,
  };
}

describe("collectBagRuns", () => {
  it("collapses each bag into one run with its span and total", () => {
    const c = (grams: number) => [
      { bean_id: "b1", bean_name: "Ethiopia Guji", roaster: "Square Mile", grams },
    ];
    const runs = collectBagRuns([
      makeDay("2026-06-21", c(45)),
      makeDay("2026-06-22", c(45)),
      makeDay("2026-06-23", c(30)),
    ]);

    expect(runs).toHaveLength(1);
    expect(runs[0]).toMatchObject({
      beanId: "b1",
      start: "2026-06-21",
      end: "2026-06-23",
      grams: 120,
    });
  });

  it("keeps bags in the order they are first drunk", () => {
    const runs = collectBagRuns([
      makeDay("2026-06-21", [
        { bean_id: "b1", bean_name: "First", roaster: "A", grams: 45 },
      ]),
      makeDay("2026-06-22", [
        { bean_id: "b2", bean_name: "Second", roaster: "B", grams: 45 },
      ]),
    ]);
    expect(runs.map((r) => r.name)).toEqual(["First", "Second"]);
  });
});

describe("renderBagList", () => {
  it("names each bag and its date range", () => {
    const html = renderBagList([
      {
        beanId: "b1",
        name: "Ethiopia Guji",
        roaster: "Square Mile",
        start: "2026-06-21",
        end: "2026-06-23",
        grams: 120,
      },
    ]);
    expect(html).toContain("Ethiopia Guji");
    expect(html).toContain("Jun 21 → Jun 23");
    expect(html).toContain("120 g");
  });

  it("collapses a single-day run to one date", () => {
    const html = renderBagList([
      {
        beanId: "b1",
        name: "Ethiopia Guji",
        roaster: "Square Mile",
        start: "2026-06-21",
        end: "2026-06-21",
        grams: 45,
      },
    ]);
    expect(html).toContain("Jun 21 ·");
    expect(html).not.toContain("→");
  });

  it("renders nothing when there are no bags", () => {
    expect(renderBagList([])).toBe("");
  });
});

describe("REHIGHLIGHT_SCRIPT", () => {
  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = "";
  });

  function buildGrid(dates: string[], bakedTodayDate?: string): void {
    document.body.innerHTML = dates
      .map((d) => {
        const isToday = d === bakedTodayDate;
        return renderDayCell(makeCell({ date: d, isToday }));
      })
      .join("");
  }

  it("moves the today class onto the cell matching the viewer's current date", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-06-23T09:00:00"));

    // Page generated on the 21st, so the 21st is baked as today.
    buildGrid(["2026-06-21", "2026-06-22", "2026-06-23"], "2026-06-21");

    // eslint-disable-next-line no-eval
    eval(REHIGHLIGHT_SCRIPT);

    expect(document.querySelector('[data-date="2026-06-21"]')!.className).not.toContain("today");
    expect(document.querySelector('[data-date="2026-06-23"]')!.className).toContain("today");
    expect(document.querySelectorAll(".cell.today")).toHaveLength(1);
  });

  it("leaves nothing highlighted when the current date is not on the page", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-01T09:00:00"));

    buildGrid(["2026-06-21", "2026-06-22"], "2026-06-21");

    // eslint-disable-next-line no-eval
    eval(REHIGHLIGHT_SCRIPT);

    expect(document.querySelectorAll(".cell.today")).toHaveLength(0);
  });
});
