import { getRoasterColor, RoasterColor } from "./colors";
import { ScheduleDay } from "./types";

export interface MonthData {
  label: string; // "March"
  year: string; // "2026"
  weeks: (DayCellData | null)[][]; // 7-col grid, null = empty cell
}

export interface DayCellData {
  date: string;
  dayNum: number;
  isToday: boolean;
  isGap: boolean;
  isSkip: boolean;
  consumptions: ScheduleDay["consumptions"];
}

/** One bag's run through the schedule, for the key beneath the calendar. */
export interface BagRun {
  beanId: string;
  name: string;
  roaster: string;
  start: string;
  end: string;
  grams: number;
}

/** How a roaster maps to a colour for this render. */
export type RoasterPalette = (roaster: string) => RoasterColor;

export function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function shortDay(iso: string): string {
  return new Date(iso + "T00:00:00Z").toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  });
}

/**
 * A day is a date number plus a colour stripe per bag. Names never fit at this
 * width — they live in the key below the calendar and in the tap-through
 * detail, so the grid only has to carry "which bag, and is anything wrong".
 */
export function renderDayCell(
  cell: DayCellData | null,
  colorFor: RoasterPalette = getRoasterColor
): string {
  if (!cell) return `<div class="cell empty"></div>`;

  const classes = ["cell"];
  if (cell.isToday) classes.push("today");
  if (cell.isGap) classes.push("gap");
  if (cell.isSkip) classes.push("skip");

  let stripes = "";
  const detailLines: string[] = [];

  const d = new Date(cell.date + "T00:00:00Z");
  const dayLabel = d.toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
  detailLines.push(`<strong>${escapeHtml(dayLabel)}</strong>`);

  for (const c of cell.consumptions) {
    const color = colorFor(c.roaster);
    stripes += `<span class="stripe" style="background:${color.border}"></span>`;
    detailLines.push(
      `<div class="modal-row" style="border-color:${color.border}"><span class="modal-name">${escapeHtml(c.bean_name)}</span><span class="modal-meta">${Math.round(c.grams)} g · ${escapeHtml(c.roaster)}</span></div>`
    );
  }
  if (cell.isGap) {
    stripes += `<span class="stripe gap-stripe"></span>`;
    detailLines.push(`<div class="modal-note gap-note">No coffee scheduled</div>`);
  }
  if (cell.isSkip) {
    stripes += `<span class="stripe skip-stripe"></span>`;
    detailLines.push(`<div class="modal-note">Skip day — nothing brewed</div>`);
  }

  const hasDetail = cell.consumptions.length > 0 || cell.isGap || cell.isSkip;
  const detailAttr = hasDetail
    ? ` data-detail="${escapeHtml(detailLines.join(""))}"`
    : "";

  return `<div class="${classes.join(" ")}" data-date="${cell.date}"${detailAttr}><span class="day-num">${cell.dayNum}</span><span class="stripes">${stripes}</span></div>`;
}

export function renderMonth(
  m: MonthData,
  colorFor: RoasterPalette = getRoasterColor
): string {
  let html = `<section class="month"><h2>${escapeHtml(m.label)} <span class="year">${escapeHtml(m.year)}</span></h2><div class="cal-grid">`;
  for (const day of ["M", "T", "W", "T", "F", "S", "S"]) {
    html += `<div class="hdr">${day}</div>`;
  }
  for (const week of m.weeks) {
    for (const cell of week) {
      html += renderDayCell(cell, colorFor);
    }
  }
  html += `</div></section>`;
  return html;
}

/** The key: which colour is which bag, and when it is being drunk. */
export function renderBagList(
  bags: BagRun[],
  colorFor: RoasterPalette = getRoasterColor
): string {
  if (bags.length === 0) return "";
  let html = `<section class="bags"><h2>Bags in this schedule</h2>`;
  for (const bag of bags) {
    const color = colorFor(bag.roaster);
    const range =
      bag.start === bag.end
        ? shortDay(bag.start)
        : `${shortDay(bag.start)} → ${shortDay(bag.end)}`;
    html += `<div class="bag"><span class="bag-rail" style="background:${color.border}"></span><div class="bag-text"><div class="bag-name">${escapeHtml(bag.name)}</div><div class="bag-meta">${escapeHtml(bag.roaster)} · ${range} · ${Math.round(bag.grams)} g</div></div></div>`;
  }
  html += `</section>`;
  return html;
}

/** Collapse the schedule into one run per bag, in the order they are drunk. */
export function collectBagRuns(schedule: ScheduleDay[]): BagRun[] {
  const runs = new Map<string, BagRun>();
  for (const day of schedule) {
    for (const c of day.consumptions) {
      const existing = runs.get(c.bean_id);
      if (existing) {
        existing.end = day.date;
        existing.grams += c.grams;
      } else {
        runs.set(c.bean_id, {
          beanId: c.bean_id,
          name: c.bean_name,
          roaster: c.roaster,
          start: day.date,
          end: day.date,
          grams: c.grams,
        });
      }
    }
  }
  return [...runs.values()];
}

// Client-side script (runs in the published page) that re-highlights "today"
// based on the viewer's current date rather than the date the page was
// generated. Each cell carries a data-date="YYYY-MM-DD" attribute. Falls back
// to the baked-in highlight if JS is disabled. Exposed as a string so it can be
// embedded verbatim in the generated HTML and exercised in tests.
export const REHIGHLIGHT_SCRIPT = `(function(){
  var now=new Date();
  var iso=now.getFullYear()+"-"+String(now.getMonth()+1).padStart(2,"0")+"-"+String(now.getDate()).padStart(2,"0");
  document.querySelectorAll(".cell.today").forEach(function(c){c.classList.remove("today");});
  var todayCell=document.querySelector('.cell[data-date="'+iso+'"]');
  if(todayCell)todayCell.classList.add("today");
})();`;
