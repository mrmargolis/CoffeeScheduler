import { describe, it, expect, afterEach, vi } from "vitest";
import {
  DayRowData,
  WeekData,
  collectBagRuns,
  groupIntoWeeks,
  renderBagList,
  renderDayRow,
  renderWeek,
  renderWeekNav,
  weekIndexFor,
  weekLabel,
  WEEK_NAV_SCRIPT,
} from "@/lib/schedule-html";
import { ScheduleDay } from "@/lib/types";

function makeRow(overrides: Partial<DayRowData> = {}): DayRowData {
  return {
    date: "2026-06-21",
    dayNum: 21,
    isToday: false,
    isPast: false,
    isGap: false,
    isSkip: false,
    isActual: false,
    consumptions: [],
    ...overrides,
  };
}

describe("renderDayRow", () => {
  const guji = [
    { bean_id: "b1", bean_name: "Ethiopia Guji", roaster: "Square Mile", grams: 45 },
  ];

  it("names the bag, its dose and its roaster on the row itself", () => {
    const html = renderDayRow(makeRow({ consumptions: guji }));

    expect(html).toContain(">Ethiopia Guji<");
    expect(html).toContain("45 g · Square Mile");
  });

  it("carries the ISO date and the weekday for the row", () => {
    const html = renderDayRow(makeRow({ date: "2026-06-21", dayNum: 21 }));

    expect(html).toContain('data-date="2026-06-21"');
    expect(html).toContain(">Sun<");
    expect(html).toContain(">21<");
  });

  it("lists every bag on a transition day", () => {
    const html = renderDayRow(
      makeRow({
        consumptions: [
          ...guji,
          { bean_id: "b2", bean_name: "Kenya Kii", roaster: "La Cabra", grams: 15 },
        ],
      })
    );

    expect(html).toContain("Ethiopia Guji");
    expect(html).toContain("Kenya Kii");
    expect(html).toContain("15 g · La Cabra");
  });

  it("flags a projected day with nothing available", () => {
    const html = renderDayRow(makeRow({ isGap: true }));

    expect(html).toContain("Nothing available");
    expect(html).toContain("gap");
  });

  it("says a past day has no brews logged rather than leaving it blank", () => {
    // A past day the scheduler flagged as a gap is one with no recorded brews —
    // an unlogged day, not a projected shortage.
    const html = renderDayRow(
      makeRow({ isPast: true, isGap: true, isActual: true })
    );

    expect(html).toContain("No brews logged");
    expect(html).not.toContain("Nothing available");
  });

  it("marks skip days", () => {
    expect(renderDayRow(makeRow({ isSkip: true }))).toContain("Skip day");
  });

  it("dims past days and marks today, without baking a Today label into the markup", () => {
    expect(renderDayRow(makeRow({ isPast: true }))).toContain('class="day past"');

    const todayHtml = renderDayRow(makeRow({ isToday: true }));
    expect(todayHtml).toContain('class="day today"');
    // The label is drawn from the today class by CSS, so the script below can
    // move it to the viewer's date.
    expect(todayHtml).not.toContain("Today");
  });
});

describe("renderWeek", () => {
  function week(days: DayRowData[]): WeekData {
    return { days };
  }

  const bag = [
    { bean_id: "b1", bean_name: "Ethiopia Guji", roaster: "Square Mile", grams: 45 },
  ];

  it("carries its span and label so the script can pick and title it", () => {
    const html = renderWeek(
      week([
        makeRow({ date: "2026-10-05", dayNum: 5, consumptions: bag }),
        makeRow({ date: "2026-10-11", dayNum: 11, consumptions: bag }),
      ])
    );

    expect(html).toContain('data-start="2026-10-05"');
    expect(html).toContain('data-end="2026-10-11"');
    expect(html).toContain('data-label="Oct 5 – Oct 11"');
  });

  it("hides every week but the one asked for, so the page opens on one", () => {
    const w = week([makeRow({ date: "2026-10-05", dayNum: 5 })]);

    expect(renderWeek(w)).toContain("<section class=\"week\" data-start=\"2026-10-05\" data-end=\"2026-10-05\" data-label=\"Oct 5\" hidden>");
    expect(renderWeek(w, undefined, true)).not.toContain("hidden");
  });

  it("collapses a run of empty days into one row", () => {
    const days = [5, 6, 7, 8].map((dayNum) =>
      makeRow({ date: `2026-10-0${dayNum}`, dayNum, isGap: true })
    );

    const html = renderWeek(week(days));

    expect(html.match(/Nothing available/g)).toHaveLength(1);
    expect(html).toContain("4 days through Oct 8");
    // The run keeps both ends so the viewer's date can still be placed in it.
    expect(html).toContain('data-date="2026-10-05" data-end="2026-10-08"');
  });

  it("keeps a lone empty day as its own row", () => {
    const html = renderWeek(
      week([
        makeRow({ date: "2026-10-05", dayNum: 5, consumptions: bag }),
        makeRow({ date: "2026-10-06", dayNum: 6, isGap: true }),
        makeRow({ date: "2026-10-07", dayNum: 7, consumptions: bag }),
      ])
    );

    expect(html).toContain("Nothing available");
    expect(html).not.toContain("days through");
  });

  it("does not merge runs of different kinds", () => {
    const html = renderWeek(
      week([
        makeRow({ date: "2026-10-05", dayNum: 5, isSkip: true }),
        makeRow({ date: "2026-10-06", dayNum: 6, isSkip: true }),
        makeRow({ date: "2026-10-07", dayNum: 7, isGap: true }),
        makeRow({ date: "2026-10-08", dayNum: 8, isGap: true }),
      ])
    );

    expect(html).toContain("Skip days · 2 days through Oct 6");
    expect(html).toContain("Nothing available · 2 days through Oct 8");
  });

  it("never collapses days that have coffee on them", () => {
    const html = renderWeek(
      week([5, 6, 7].map((dayNum) =>
        makeRow({ date: `2026-10-0${dayNum}`, dayNum, consumptions: bag })
      ))
    );

    expect(html.match(/Ethiopia Guji/g)).toHaveLength(3);
  });
});

describe("groupIntoWeeks", () => {
  function daysFrom(start: string, count: number): DayRowData[] {
    const out: DayRowData[] = [];
    const d = new Date(start + "T00:00:00Z");
    for (let i = 0; i < count; i++) {
      const iso = d.toISOString().slice(0, 10);
      out.push(makeRow({ date: iso, dayNum: d.getUTCDate() }));
      d.setUTCDate(d.getUTCDate() + 1);
    }
    return out;
  }

  it("breaks on Mondays", () => {
    // Sep 1 2026 is a Tuesday, so the first week is a short one.
    const weeks = groupIntoWeeks(daysFrom("2026-09-01", 14));

    expect(weeks.map((w) => w.days.length)).toEqual([6, 7, 1]);
    expect(weeks[1].days[0].date).toBe("2026-09-07"); // a Monday
    expect(weekLabel(weeks[0])).toBe("Sep 1 – Sep 6");
  });

  it("labels a one-day week with the single date", () => {
    expect(weekLabel({ days: daysFrom("2026-09-14", 1) })).toBe("Sep 14");
  });
});

describe("weekIndexFor", () => {
  const weeks = groupIntoWeeks(
    ["2026-09-07", "2026-09-08", "2026-09-14", "2026-09-21"].map((date) =>
      makeRow({ date, dayNum: Number(date.slice(8)) })
    )
  );

  it("finds the week holding the date", () => {
    expect(weekIndexFor(weeks, "2026-09-08")).toBe(0);
    expect(weekIndexFor(weeks, "2026-09-14")).toBe(1);
  });

  it("clamps to the last week for a date past the end of the schedule", () => {
    expect(weekIndexFor(weeks, "2026-12-25")).toBe(weeks.length - 1);
  });

  it("clamps to the first week for a date before the schedule starts", () => {
    expect(weekIndexFor(weeks, "2026-01-01")).toBe(0);
  });
});

describe("renderWeekNav", () => {
  const weeks = groupIntoWeeks(
    ["2026-09-07", "2026-09-14", "2026-09-21"].map((date) =>
      makeRow({ date, dayNum: Number(date.slice(8)) })
    )
  );

  it("disables the button that would run off the end of the schedule", () => {
    expect(renderWeekNav(weeks, 0)).toContain('id="week-prev" class="navbtn" aria-label="Previous week" disabled');
    expect(renderWeekNav(weeks, 0)).not.toContain('aria-label="Next week" disabled');

    expect(renderWeekNav(weeks, 2)).toContain('aria-label="Next week" disabled');
    expect(renderWeekNav(weeks, 1)).not.toContain("disabled");
  });

  it("titles itself with the week it opens on", () => {
    expect(renderWeekNav(weeks, 1)).toContain(">Sep 14<");
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

describe("WEEK_NAV_SCRIPT", () => {
  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = "";
  });

  /** Three weeks of plain days, Sep 7 through Sep 27, as the page would ship. */
  function buildPage(generatedOn: string): void {
    const days: DayRowData[] = [];
    const d = new Date("2026-09-07T00:00:00Z");
    for (let i = 0; i < 21; i++) {
      const iso = d.toISOString().slice(0, 10);
      days.push(
        makeRow({
          date: iso,
          dayNum: d.getUTCDate(),
          isToday: iso === generatedOn,
          isPast: iso < generatedOn,
        })
      );
      d.setUTCDate(d.getUTCDate() + 1);
    }
    const weeks = groupIntoWeeks(days);
    const initial = weekIndexFor(weeks, generatedOn);
    document.body.innerHTML =
      renderWeekNav(weeks, initial) +
      weeks.map((w, i) => renderWeek(w, undefined, i === initial)).join("");
  }

  function visibleWeek(): string | null {
    const shown = [...document.querySelectorAll<HTMLElement>(".week")].filter(
      (w) => !w.hidden
    );
    expect(shown).toHaveLength(1);
    return shown[0].getAttribute("data-label");
  }

  function run(): void {
    // eslint-disable-next-line no-eval
    eval(WEEK_NAV_SCRIPT);
  }

  it("opens on the week holding the viewer's date, not the week it was generated in", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-16T09:00:00"));

    buildPage("2026-09-08"); // published the week before

    run();

    expect(visibleWeek()).toBe("Sep 14 – Sep 20");
    expect(document.getElementById("week-label")!.textContent).toBe("Sep 14 – Sep 20");
  });

  it("moves a week at a time and keeps the label in step", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-16T09:00:00"));
    buildPage("2026-09-16");
    run();

    document.getElementById("week-prev")!.click();
    expect(visibleWeek()).toBe("Sep 7 – Sep 13");

    document.getElementById("week-next")!.click();
    document.getElementById("week-next")!.click();
    expect(visibleWeek()).toBe("Sep 21 – Sep 27");
  });

  it("disables the buttons at the ends of the published range", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-16T09:00:00"));
    buildPage("2026-09-16");
    run();

    const prev = document.getElementById("week-prev") as HTMLButtonElement;
    const next = document.getElementById("week-next") as HTMLButtonElement;
    expect(prev.disabled).toBe(false);
    expect(next.disabled).toBe(false);

    prev.click();
    expect(prev.disabled).toBe(true);
    expect(next.disabled).toBe(false);

    next.click();
    next.click();
    expect(next.disabled).toBe(true);
  });

  it("clamps to the last week when the page has been left behind", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-11-02T09:00:00"));

    buildPage("2026-09-08");
    run();

    expect(visibleWeek()).toBe("Sep 21 – Sep 27");
    expect((document.getElementById("week-next") as HTMLButtonElement).disabled).toBe(true);
  });

  it("re-marks today and the days behind it from the viewer's clock", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-16T09:00:00"));

    buildPage("2026-09-08"); // the 8th is baked as today

    run();

    expect(document.querySelector('[data-date="2026-09-08"]')!.className).toContain("past");
    expect(document.querySelector('[data-date="2026-09-16"]')!.className).toContain("today");
    expect(document.querySelectorAll(".day.today")).toHaveLength(1);
    expect(document.querySelector('[data-date="2026-09-17"]')!.className).not.toContain("past");
  });

  it("places today inside a collapsed run of empty days", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-16T09:00:00"));

    const days = [14, 15, 16, 17, 18, 19, 20].map((dayNum) =>
      makeRow({ date: `2026-09-${dayNum}`, dayNum, isGap: true })
    );
    const weeks = groupIntoWeeks(days);
    document.body.innerHTML =
      renderWeekNav(weeks, 0) + renderWeek(weeks[0], undefined, true);

    run();

    const collapsed = document.querySelector(".day.run")!;
    expect(collapsed.className).toContain("today");
    expect(document.querySelectorAll(".day.today")).toHaveLength(1);
  });

  it("steps weeks with the arrow keys", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-09-16T09:00:00"));
    buildPage("2026-09-16");
    run();

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft" }));
    expect(visibleWeek()).toBe("Sep 7 – Sep 13");

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight" }));
    expect(visibleWeek()).toBe("Sep 14 – Sep 20");
  });
});
