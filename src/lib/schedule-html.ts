import { getRoasterColor } from "./colors";
import { ScheduleDay } from "./types";

export interface MonthData {
  label: string; // "March 2026"
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

export function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

export function renderDayCell(cell: DayCellData | null): string {
  if (!cell) return `<div class="cell empty"></div>`;

  const classes = ["cell"];
  if (cell.isToday) classes.push("today");
  if (cell.isGap) classes.push("gap");
  if (cell.isSkip) classes.push("skip");

  let pills = "";
  const detailLines: string[] = [];

  // Format date label for modal: "Tue Mar 3"
  const d = new Date(cell.date + "T00:00:00Z");
  const dayLabel = d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" });
  detailLines.push(`<strong>${escapeHtml(dayLabel)}</strong>`);

  for (const c of cell.consumptions) {
    const color = getRoasterColor(c.roaster);
    pills += `<div class="pill" style="background:${color.bg};border-color:${color.border};color:${color.text}">${Math.round(c.grams)}g ${escapeHtml(c.bean_name)}</div>`;
    detailLines.push(`<div class="modal-pill" style="background:${color.bg};border-color:${color.border};color:${color.text}">${Math.round(c.grams)}g ${escapeHtml(c.bean_name)}</div>`);
  }
  if (cell.isGap) {
    pills += `<div class="pill gap-pill">No coffee!</div>`;
    detailLines.push(`<div class="modal-pill gap-pill">No coffee!</div>`);
  }
  if (cell.isSkip) {
    pills += `<div class="pill skip-pill">Skip</div>`;
    detailLines.push(`<div class="modal-pill skip-pill">Skip</div>`);
  }

  const hasDetail = cell.consumptions.length > 0 || cell.isGap || cell.isSkip;
  const detailAttr = hasDetail ? ` data-detail="${escapeHtml(detailLines.join(""))}"` : "";

  return `<div class="${classes.join(" ")}" data-date="${cell.date}"${detailAttr}><span class="day-num">${cell.dayNum}</span>${pills}</div>`;
}

export function renderMonth(m: MonthData): string {
  let html = `<h2>${escapeHtml(m.label)}</h2><div class="cal-grid"><div class="hdr">Mon</div><div class="hdr">Tue</div><div class="hdr">Wed</div><div class="hdr">Thu</div><div class="hdr">Fri</div><div class="hdr">Sat</div><div class="hdr">Sun</div>`;
  for (const week of m.weeks) {
    for (const cell of week) {
      html += renderDayCell(cell);
    }
  }
  html += `</div>`;
  return html;
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
