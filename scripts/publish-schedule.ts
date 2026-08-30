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
import { ScheduleDay } from "../src/lib/types";
import {
  DayCellData,
  MonthData,
  escapeHtml,
  renderMonth,
  REHIGHLIGHT_SCRIPT,
} from "../src/lib/schedule-html";

const dryRun = process.argv.includes("--dry-run");

// --- Load data ---

const db = getDb(path.join(process.cwd(), "data", "coffee.db"));
const today = getToday();

autoThawBeans(db, today);
autoFreezeBeans(db, today);

// Schedule spans the 1st of the current month through the end of next month so
// the calendar shows past brews (actual history) alongside the future
// projection. Past days without recorded brews are flagged is_actual by the
// scheduler, so the gap marking below suppresses their "No coffee!" indicator.
const now = new Date();
const startDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-01`;
const endMonth = new Date(now.getFullYear(), now.getMonth() + 2, 0); // last day of next month
const endDate = `${endMonth.getFullYear()}-${String(endMonth.getMonth() + 1).padStart(2, "0")}-${String(endMonth.getDate()).padStart(2, "0")}`;

const { schedule, skipDayRanges } = loadScheduleData(db, startDate, endDate, today);
const { summary } = buildCalendarEvents(schedule, skipDayRanges, today);

closeDb();

// --- Build calendar data structures ---

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
        // Mirror the dynamic calendar: only projected gaps are flagged. Past
        // empty days are is_actual, so they render blank rather than "No coffee!".
        isGap: (sched?.is_gap ?? false) && !(sched?.is_actual ?? false),
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
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Cpath d='M6 8h16v2h3a4 4 0 0 1 0 8h-3v2a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4V8z' fill='%238B6914'/%3E%3Cpath d='M22 10h3a2 2 0 0 1 0 4h-3v-4z' fill='%23A07D1A'/%3E%3Cpath d='M8 10h12v9a3 3 0 0 1-3 3h-6a3 3 0 0 1-3-3v-9z' fill='%23C4942A'/%3E%3Cpath d='M8 10h12v2H8z' fill='%23D4A43A' opacity='0.6'/%3E%3Cpath d='M7 26h14a1 1 0 0 1 0 2H7a1 1 0 0 1 0-2z' fill='%238B6914'/%3E%3Cellipse cx='14' cy='6' rx='2' ry='2' fill='%23D4A43A' opacity='0.4'/%3E%3Cellipse cx='11' cy='5' rx='1.5' ry='1.5' fill='%23D4A43A' opacity='0.3'/%3E%3Cellipse cx='17' cy='5' rx='1.5' ry='1.5' fill='%23D4A43A' opacity='0.3'/%3E%3C/svg%3E">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#141110;color:#e9e6e0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;font-size:14px;padding:12px;max-width:700px;margin:0 auto}
h1{font-size:1.3rem;text-align:center;margin-bottom:8px;font-weight:600}
h2{font-size:1rem;margin:16px 0 6px;font-weight:600}
.summary{text-align:center;padding:8px 12px;border-radius:8px;margin-bottom:12px;font-weight:600;font-size:0.95rem}
.ok-summary{background:#182a1c;border:1px solid #2f5238;color:#91cb9c}
.gap-summary{background:#2f1b18;border:1px solid #5c3630;color:#ea8e82}
.cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:2px}
.hdr{text-align:center;font-size:0.7rem;color:#807b74;padding:4px 0;font-weight:600}
.cell{background:#1c1917;border-radius:4px;min-height:48px;padding:3px;overflow:hidden;position:relative}
.cell.empty{background:transparent}
.cell.today{outline:2px solid #e5a152;outline-offset:-1px}
.cell.gap{background:#241614}
.cell.skip{background:#1f1c1a}
.day-num{font-size:0.7rem;color:#aea8a1;display:block;margin-bottom:1px}
.pill{font-size:0.55rem;padding:1px 4px;border-radius:3px;border-left:3px solid;margin-bottom:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.3}
.gap-pill{background:#2f1b18;border-color:#ea8e82;color:#f0cdc7}
.skip-pill{background:#1f1c1a;border-color:#3d3833;color:#807b74}
.footer{text-align:center;color:#807b74;font-size:0.7rem;margin-top:16px;padding-bottom:env(safe-area-inset-bottom,12px)}
.cell[data-detail]{cursor:pointer}
.modal{position:fixed;inset:0;background:rgba(0,0,0,0.6);display:flex;align-items:center;justify-content:center;z-index:100;padding:24px}
.modal.hidden{display:none}
.modal-card{background:#1c1917;border:1px solid #3d3833;border-radius:12px;padding:16px 20px;max-width:320px;width:100%;color:#e9e6e0;font-size:0.95rem;line-height:1.6}
.modal-card strong{font-size:1.1rem}
.modal-pill{font-size:0.85rem;padding:4px 10px;border-radius:6px;border-left:3px solid;margin-top:6px;line-height:1.4}
</style>
</head>
<body>
<h1>Coffee Schedule</h1>
${summaryHtml}
${months.map(renderMonth).join("\n")}
<div class="footer">Generated ${escapeHtml(generatedAt)}</div>
<div id="modal" class="modal hidden"></div>
<script>
${REHIGHLIGHT_SCRIPT}
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
