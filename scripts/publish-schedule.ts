import path from "path";
import fs from "fs";
import os from "os";
import { execSync } from "child_process";
import { getDb, closeDb } from "../src/lib/db";
import { today as getToday } from "../src/lib/date-utils";
import { autoThawBeans } from "../src/lib/auto-thaw";
import { autoFreezeBeans } from "../src/lib/auto-freeze";
import { loadScheduleData } from "../src/lib/schedule-loader";
import { buildCalendarEvents } from "../src/lib/calendar-utils";
import { getRoasterColor } from "../src/lib/colors";
import { ScheduleDay } from "../src/lib/types";

const dryRun = process.argv.includes("--dry-run");

// --- Load data ---

const db = getDb(path.join(process.cwd(), "coffee.db"));
const today = getToday();

autoThawBeans(db, today);
autoFreezeBeans(db, today);

// Date range: 1st of current month through end of next month
const now = new Date();
const startDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-01`;
const endMonth = new Date(now.getFullYear(), now.getMonth() + 2, 0); // last day of next month
const endDate = `${endMonth.getFullYear()}-${String(endMonth.getMonth() + 1).padStart(2, "0")}-${String(endMonth.getDate()).padStart(2, "0")}`;

const { schedule, skipDayRanges } = loadScheduleData(db, startDate, endDate, today);
const { summary } = buildCalendarEvents(schedule, skipDayRanges, today);

closeDb();

// --- Build calendar data structures ---

interface MonthData {
  label: string; // "March 2026"
  weeks: (DayCellData | null)[][]; // 7-col grid, null = empty cell
}

interface DayCellData {
  date: string;
  dayNum: number;
  isToday: boolean;
  isGap: boolean;
  isSkip: boolean;
  consumptions: ScheduleDay["consumptions"];
}

// Group schedule days by month
const scheduleMap = new Map<string, ScheduleDay>();
for (const day of schedule) {
  scheduleMap.set(day.date, day);
}

function buildMonths(): MonthData[] {
  const months: MonthData[] = [];
  const start = new Date(startDate + "T00:00:00Z");
  const end = new Date(endDate + "T00:00:00Z");

  let cursor = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1));

  while (cursor <= end) {
    const year = cursor.getUTCFullYear();
    const month = cursor.getUTCMonth();
    const label = cursor.toLocaleDateString("en-US", {
      month: "long",
      year: "numeric",
      timeZone: "UTC",
    });

    const daysInMonth = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
    // Monday=0 .. Sunday=6
    const firstDow = (new Date(Date.UTC(year, month, 1)).getUTCDay() + 6) % 7;

    const cells: (DayCellData | null)[] = [];
    // Leading blanks
    for (let i = 0; i < firstDow; i++) cells.push(null);

    for (let d = 1; d <= daysInMonth; d++) {
      const iso = `${year}-${String(month + 1).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
      const sched = scheduleMap.get(iso);
      cells.push({
        date: iso,
        dayNum: d,
        isToday: iso === today,
        isGap: sched?.is_gap ?? false,
        isSkip: sched?.is_skip ?? false,
        consumptions: sched?.consumptions ?? [],
      });
    }

    // Pad trailing blanks to fill last week
    while (cells.length % 7 !== 0) cells.push(null);

    // Split into weeks
    const weeks: (DayCellData | null)[][] = [];
    for (let i = 0; i < cells.length; i += 7) {
      weeks.push(cells.slice(i, i + 7));
    }

    months.push({ label, weeks });
    cursor = new Date(Date.UTC(year, month + 1, 1));
  }

  return months;
}

const months = buildMonths();

// --- Generate HTML ---

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function renderDayCell(cell: DayCellData | null): string {
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

  return `<div class="${classes.join(" ")}"${detailAttr}><span class="day-num">${cell.dayNum}</span>${pills}</div>`;
}

function renderMonth(m: MonthData): string {
  let html = `<h2>${escapeHtml(m.label)}</h2><div class="cal-grid"><div class="hdr">Mon</div><div class="hdr">Tue</div><div class="hdr">Wed</div><div class="hdr">Thu</div><div class="hdr">Fri</div><div class="hdr">Sat</div><div class="hdr">Sun</div>`;
  for (const week of m.weeks) {
    for (const cell of week) {
      html += renderDayCell(cell);
    }
  }
  html += `</div>`;
  return html;
}

let summaryHtml = "";
if (summary) {
  if (summary.nextGapDate) {
    summaryHtml = `<div class="summary gap-summary">Gap on ${summary.nextGapDate}</div>`;
  } else {
    summaryHtml = `<div class="summary ok-summary">${summary.daysOfCoffee} days of coffee remaining</div>`;
  }
}

const generatedAt = new Date().toLocaleString("en-US", {
  dateStyle: "medium",
  timeStyle: "short",
});

const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<title>Coffee Schedule</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#030712;color:#C9D1D9;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;font-size:14px;padding:12px;max-width:700px;margin:0 auto}
h1{font-size:1.3rem;text-align:center;margin-bottom:8px;font-weight:600}
h2{font-size:1rem;margin:16px 0 6px;font-weight:600}
.summary{text-align:center;padding:8px 12px;border-radius:8px;margin-bottom:12px;font-weight:600;font-size:0.95rem}
.ok-summary{background:#0d1f0d;border:1px solid #3FB950;color:#3FB950}
.gap-summary{background:#1c1010;border:1px solid #F85149;color:#F85149}
.cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:2px}
.hdr{text-align:center;font-size:0.7rem;color:#6E7681;padding:4px 0;font-weight:600}
.cell{background:#111827;border-radius:4px;min-height:48px;padding:3px;overflow:hidden;position:relative}
.cell.empty{background:transparent}
.cell.today{outline:2px solid #58A6FF;outline-offset:-1px}
.cell.gap{background:#1a0a0a}
.cell.skip{background:#16181d}
.day-num{font-size:0.7rem;color:#8B949E;display:block;margin-bottom:1px}
.pill{font-size:0.55rem;padding:1px 3px;border-radius:3px;border:1px solid;margin-bottom:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.3}
.gap-pill{background:#1c1010;border-color:#F85149;color:#F85149}
.skip-pill{background:#161B22;border-color:#6E7681;color:#8B949E}
.footer{text-align:center;color:#6E7681;font-size:0.7rem;margin-top:16px;padding-bottom:env(safe-area-inset-bottom,12px)}
.cell[data-detail]{cursor:pointer}
.modal{position:fixed;inset:0;background:rgba(0,0,0,0.6);display:flex;align-items:center;justify-content:center;z-index:100;padding:24px}
.modal.hidden{display:none}
.modal-card{background:#161B22;border:1px solid #30363D;border-radius:12px;padding:16px 20px;max-width:320px;width:100%;color:#C9D1D9;font-size:0.95rem;line-height:1.6}
.modal-card strong{font-size:1.1rem}
.modal-pill{font-size:0.85rem;padding:4px 8px;border-radius:6px;border:1px solid;margin-top:6px;line-height:1.4}
</style>
</head>
<body>
<h1>Coffee Schedule</h1>
${summaryHtml}
${months.map(renderMonth).join("\n")}
<div class="footer">Generated ${escapeHtml(generatedAt)}</div>
<div id="modal" class="modal hidden"></div>
<script>
(function(){
  var modal=document.getElementById("modal");
  document.querySelectorAll(".cell[data-detail]").forEach(function(cell){
    cell.addEventListener("click",function(e){
      e.stopPropagation();
      modal.innerHTML='<div class="modal-card">'+cell.getAttribute("data-detail")+'</div>';
      modal.classList.remove("hidden");
    });
  });
  modal.addEventListener("click",function(){modal.classList.add("hidden");});
})();
</script>
</body>
</html>`;

// --- Deploy or dry-run ---

if (dryRun) {
  const outDir = path.join(process.cwd(), "tmp");
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, "schedule.html");
  fs.writeFileSync(outPath, html);
  console.log(`Dry run: wrote ${outPath}`);
} else {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "coffee-schedule-"));
  const indexPath = path.join(tmpDir, "index.html");
  fs.writeFileSync(indexPath, html);

  try {
    execSync("git init", { cwd: tmpDir, stdio: "pipe" });
    execSync("git add index.html", { cwd: tmpDir, stdio: "pipe" });
    execSync('git commit -m "Update coffee schedule"', { cwd: tmpDir, stdio: "pipe" });
    execSync(
      "git push --force git@github.com:mrmargolis/CoffeeScheduler.git HEAD:gh-pages",
      { cwd: tmpDir, stdio: "inherit" }
    );
    console.log("Published to GitHub Pages!");
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}
