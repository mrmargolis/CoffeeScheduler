import { describe, it, expect, afterEach, vi } from "vitest";
import {
  DayCellData,
  renderDayCell,
  REHIGHLIGHT_SCRIPT,
} from "@/lib/schedule-html";

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
