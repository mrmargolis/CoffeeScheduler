import { getRoasterColor, RoasterColor } from "./colors";
import { ScheduleDay } from "./types";

/** One Monday-to-Sunday page of the schedule. Edge weeks can be partial. */
export interface WeekData {
  days: DayRowData[];
}

export interface DayRowData {
  date: string;
  dayNum: number;
  isToday: boolean;
  isPast: boolean;
  isGap: boolean;
  isSkip: boolean;
  /** Past day standing on recorded brews rather than a projection. */
  isActual: boolean;
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
 * A day is one row: the date, then a line per bag naming what is being drunk.
 * The page is read on a phone, where a 7-column grid can only fit a colour —
 * a list gives every bag its name, grams and roaster without a tap.
 */
export function renderDayRow(
  day: DayRowData,
  colorFor: RoasterPalette = getRoasterColor
): string {
  const classes = ["day"];
  if (day.isToday) classes.push("today");
  else if (day.isPast) classes.push("past");
  if (day.isGap && !day.isActual) classes.push("gap");

  const d = new Date(day.date + "T00:00:00Z");
  const weekday = d.toLocaleDateString("en-US", {
    weekday: "short",
    timeZone: "UTC",
  });

  let body = "";
  for (const c of day.consumptions) {
    const color = colorFor(c.roaster);
    body += `<div class="brew"><span class="rail" style="background:${color.border}"></span><span class="brew-name">${escapeHtml(c.bean_name)}</span><span class="brew-meta">${Math.round(c.grams)} g · ${escapeHtml(c.roaster)}</span></div>`;
  }
  if (body === "") {
    if (day.isSkip) {
      body = `<div class="note">Skip day</div>`;
    } else if (day.isGap && day.isActual) {
      // A past day with no brews recorded. Saying so beats an empty row, which
      // reads the same as a day off and hides a BeanConqueror import that has
      // not been run yet.
      body = `<div class="note">No brews logged</div>`;
    } else if (day.isGap) {
      body = `<div class="note alert">Nothing available</div>`;
    } else {
      body = `<div class="note">—</div>`;
    }
  }

  // The "Today" marker is drawn by CSS off the today class, not baked into the
  // markup: the script below moves that class to the viewer's own date, and a
  // marker in the HTML would stay behind on the generation date.
  return `<li class="${classes.join(" ")}" data-date="${day.date}"><div class="day-date"><span class="dow">${escapeHtml(weekday)}</span><span class="dnum">${day.dayNum}</span></div><div class="day-body">${body}</div></li>`;
}

/**
 * What a day with no brews on it is: the three read very differently, and a
 * blank row would flatten them into each other.
 */
type EmptyKind = "skip" | "unlogged" | "gap" | null;

function emptyKind(day: DayRowData): EmptyKind {
  if (day.consumptions.length > 0) return null;
  if (day.isSkip) return "skip";
  // A past day the scheduler flagged as a gap has no recorded brews — it was
  // not logged, rather than short of coffee.
  if (day.isGap && day.isActual) return "unlogged";
  if (day.isGap) return "gap";
  return null;
}

const EMPTY_LABEL: Record<Exclude<EmptyKind, null>, string> = {
  skip: "Skip days",
  unlogged: "No brews logged",
  gap: "Nothing available",
};

/**
 * One row for a run of like empty days. A dry spell at the end of the schedule
 * can be most of a month, and printing it a day at a time buries the days that
 * actually have coffee on them.
 */
function renderDayRun(
  days: DayRowData[],
  kind: Exclude<EmptyKind, null>
): string {
  const first = days[0];
  const last = days[days.length - 1];
  const classes = ["day", "run"];
  if (last.isPast) classes.push("past");
  if (kind === "gap") classes.push("gap");

  const weekday = new Date(first.date + "T00:00:00Z").toLocaleDateString("en-US", {
    weekday: "short",
    timeZone: "UTC",
  });
  const note = `${EMPTY_LABEL[kind]} · ${days.length} days through ${shortDay(last.date)}`;

  return `<li class="${classes.join(" ")}" data-date="${first.date}" data-end="${last.date}"><div class="day-date"><span class="dow">${escapeHtml(weekday)}</span><span class="dnum">${first.dayNum}</span></div><div class="day-body"><div class="note${kind === "gap" ? " alert" : ""}">${escapeHtml(note)}</div></div></li>`;
}

/** Monday-first, to match the calendar in the app. Edge weeks come up short. */
export function groupIntoWeeks(days: DayRowData[]): WeekData[] {
  const weeks: WeekData[] = [];
  for (const day of days) {
    const dow = (new Date(day.date + "T00:00:00Z").getUTCDay() + 6) % 7;
    if (dow === 0 || weeks.length === 0) weeks.push({ days: [] });
    weeks[weeks.length - 1].days.push(day);
  }
  return weeks;
}

/** "Sep 7 – Sep 13", or a single date for a one-day edge week. */
export function weekLabel(week: WeekData): string {
  const first = week.days[0].date;
  const last = week.days[week.days.length - 1].date;
  return first === last ? shortDay(first) : `${shortDay(first)} – ${shortDay(last)}`;
}

/**
 * One week of rows. Every week is in the HTML; the script below reveals the one
 * holding the viewer's today and the buttons move between them, so the page
 * opens on this week without a round trip.
 */
export function renderWeek(
  week: WeekData,
  colorFor: RoasterPalette = getRoasterColor,
  visible = false
): string {
  const first = week.days[0].date;
  const last = week.days[week.days.length - 1].date;
  let html = `<section class="week" data-start="${first}" data-end="${last}" data-label="${escapeHtml(weekLabel(week))}"${visible ? "" : " hidden"}><ol class="days">`;

  for (let i = 0; i < week.days.length; ) {
    const kind = emptyKind(week.days[i]);
    if (kind) {
      let j = i;
      while (j + 1 < week.days.length && emptyKind(week.days[j + 1]) === kind) j++;
      if (j > i) {
        html += renderDayRun(week.days.slice(i, j + 1), kind);
        i = j + 1;
        continue;
      }
    }
    html += renderDayRow(week.days[i], colorFor);
    i++;
  }

  html += `</ol></section>`;
  return html;
}

/**
 * The week picker. Its label and disabled states are baked for the week that
 * was current at publish time and then corrected by the script for the viewer.
 */
export function renderWeekNav(weeks: WeekData[], initialIndex: number): string {
  const atStart = initialIndex <= 0;
  const atEnd = initialIndex >= weeks.length - 1;
  return `<nav class="weeknav"><button type="button" id="week-prev" class="navbtn" aria-label="Previous week"${atStart ? " disabled" : ""}>‹</button><span id="week-label" class="weeklabel">${escapeHtml(weekLabel(weeks[initialIndex]))}</span><button type="button" id="week-next" class="navbtn" aria-label="Next week"${atEnd ? " disabled" : ""}>›</button></nav>`;
}

/** The week holding `date`, or the nearest end of the schedule. */
export function weekIndexFor(weeks: WeekData[], date: string): number {
  for (let i = 0; i < weeks.length; i++) {
    if (date <= weeks[i].days[weeks[i].days.length - 1].date) return i;
  }
  return weeks.length - 1;
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

// Client-side script (runs in the published page). The HTML carries every week
// and bakes in "today" as of the moment it was generated; the page then sits on
// GitHub Pages until the next publish, so this re-derives today and the dimming
// of past days from the viewer's own clock and opens on the week that holds it
// — clamped to the ends of the published range when the page has gone stale.
// The buttons then step a week at a time. Rows carry data-date (and data-end on
// a collapsed run). Without JS the baked-in week stands on its own.
// Exposed as a string so it can be embedded verbatim and exercised in tests.
export const WEEK_NAV_SCRIPT = `(function(){
  var weeks=[].slice.call(document.querySelectorAll(".week"));
  if(!weeks.length)return;
  var now=new Date();
  var iso=now.getFullYear()+"-"+String(now.getMonth()+1).padStart(2,"0")+"-"+String(now.getDate()).padStart(2,"0");

  document.querySelectorAll(".day").forEach(function(row){
    var start=row.getAttribute("data-date");
    var end=row.getAttribute("data-end")||start;
    row.classList.remove("today","past");
    if(end<iso)row.classList.add("past");
    else if(start<=iso)row.classList.add("today");
  });

  var idx=weeks.length-1;
  for(var i=0;i<weeks.length;i++){
    if(iso<=weeks[i].getAttribute("data-end")){idx=i;break;}
  }

  var label=document.getElementById("week-label");
  var prev=document.getElementById("week-prev");
  var next=document.getElementById("week-next");

  function show(n){
    idx=Math.max(0,Math.min(weeks.length-1,n));
    for(var i=0;i<weeks.length;i++)weeks[i].hidden=(i!==idx);
    label.textContent=weeks[idx].getAttribute("data-label");
    prev.disabled=(idx===0);
    next.disabled=(idx===weeks.length-1);
  }

  prev.addEventListener("click",function(){show(idx-1);});
  next.addEventListener("click",function(){show(idx+1);});
  document.addEventListener("keydown",function(e){
    if(e.key==="ArrowLeft")show(idx-1);
    else if(e.key==="ArrowRight")show(idx+1);
  });
  show(idx);
})();`;
