import path from "path";
import fs from "fs";
import os from "os";
import { execSync } from "child_process";
import { getDb, closeDb } from "../src/lib/db";
import { assignRoasterColors, getRoasterColor } from "../src/lib/colors";
import { today as getToday } from "../src/lib/date-utils";
import { autoThawBeans } from "../src/lib/auto-thaw";
import { autoFreezeBeans } from "../src/lib/auto-freeze";
import { loadScheduleData } from "../src/lib/schedule-loader";
import { buildCalendarEvents } from "../src/lib/calendar-utils";
import { ScheduleDay } from "../src/lib/types";
import {
  DayCellData,
  MonthData,
  collectBagRuns,
  escapeHtml,
  renderBagList,
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

    months.push({ label, year: String(year), weeks });
    cursor = new Date(Date.UTC(year, month + 1, 1));
  }

  return months;
}

const months = buildMonths();

// --- Generate HTML ---

let summaryHtml = "";
if (summary) {
  const gap = summary.nextGapDate
    ? `<span class="runway-sub">then a gap from ${escapeHtml(
        new Date(summary.nextGapDate + "T00:00:00Z").toLocaleDateString("en-US", {
          month: "short",
          day: "numeric",
          timeZone: "UTC",
        })
      )}</span>`
    : "";
  summaryHtml = `<div class="runway${summary.nextGapDate ? " alert" : ""}"><span class="runway-num">${summary.daysOfCoffee}</span><span class="runway-text">days of coffee${gap}</span></div>`;
}

// Colour is the only thing identifying a bag in the stripe grid, so assign
// across the roasters actually on this page rather than hashing each one
// independently — otherwise two bags can land on the same colour.
const bagRuns = collectBagRuns(schedule);
const roasterColors = assignRoasterColors(bagRuns.map((b) => b.roaster));
const colorFor = (roaster: string) =>
  roasterColors.get(roaster) ?? getRoasterColor(roaster);

const bagsHtml = renderBagList(bagRuns, colorFor);

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
:root{
  --canvas:#141110;--panel:#1c1917;--raised:#241f1b;--rule:#2c2723;--rule-strong:#3d3833;--track:#322c26;
  --ink:#e9e6e0;--ink-muted:#aea8a1;--ink-faint:#807b74;
  --accent:#e5a152;--on-accent:#211603;
  --ok:#91cb9c;--ok-wash:#182a1c;--alert:#ea8e82;--alert-wash:#2f1b18;
  --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
}
body{
  background:var(--canvas);color:var(--ink);
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
  font-size:15px;line-height:1.5;-webkit-font-smoothing:antialiased;
  padding:16px 14px calc(24px + env(safe-area-inset-bottom,0px));max-width:640px;margin:0 auto;
}
.mono{font-family:var(--mono);font-variant-numeric:tabular-nums}

/* Header */
.page-head{display:flex;align-items:baseline;justify-content:space-between;gap:12px;margin-bottom:14px}
h1{font-size:19px;font-weight:600;letter-spacing:-0.02em}
.stamp{font-family:var(--mono);font-size:11px;color:var(--ink-faint)}

/* Runway */
.runway{display:flex;align-items:center;gap:12px;background:var(--panel);border:1px solid var(--rule);border-radius:12px;padding:14px 16px;margin-bottom:22px}
.runway-num{font-family:var(--mono);font-variant-numeric:tabular-nums;font-size:32px;font-weight:500;line-height:1;color:var(--ok)}
.runway.alert .runway-num{color:var(--accent)}
.runway-text{font-size:14px;color:var(--ink-muted);display:flex;flex-direction:column}
.runway-sub{font-size:12.5px;color:var(--alert);margin-top:2px}

/* Calendar */
.month{margin-bottom:24px}
h2{font-size:15px;font-weight:600;letter-spacing:-0.01em;margin-bottom:9px}
h2 .year{font-family:var(--mono);font-weight:400;color:var(--ink-faint);font-size:13px}
.cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:3px}
.hdr{text-align:center;font-family:var(--mono);font-size:10px;letter-spacing:0.09em;color:var(--ink-faint);padding:0 0 5px}
.cell{background:var(--panel);border-radius:6px;min-height:54px;padding:6px 4px 5px;display:flex;flex-direction:column;align-items:center;gap:4px}
.cell.empty{background:transparent}
.cell.gap{background:#241614}
.cell.skip{background:var(--raised)}
.day-num{font-family:var(--mono);font-variant-numeric:tabular-nums;font-size:11.5px;color:var(--ink-muted);display:flex;align-items:center;justify-content:center;width:20px;height:20px;flex:none}
.cell.today .day-num{background:var(--accent);color:var(--on-accent);border-radius:10px;font-weight:500}
.stripes{display:flex;flex-direction:column;gap:2px;width:100%;padding:0 1px}
.stripe{display:block;height:6px;border-radius:3px}
.gap-stripe{background:var(--alert)}
.skip-stripe{background:repeating-linear-gradient(115deg,var(--track) 0 3px,transparent 3px 6px)}
.cell[data-detail]{cursor:pointer}

/* Bag key */
.bags{border-top:1px solid var(--rule);padding-top:18px}
.bag{display:flex;gap:11px;padding:10px 0;border-bottom:1px solid var(--rule)}
.bag:last-child{border-bottom:0}
.bag-rail{width:3px;border-radius:2px;flex:none;align-self:stretch}
.bag-name{font-size:14px;font-weight:500;text-wrap:pretty}
.bag-meta{font-family:var(--mono);font-variant-numeric:tabular-nums;font-size:11.5px;color:var(--ink-faint);margin-top:3px}

.footer{text-align:center;color:var(--ink-faint);font-size:11.5px;margin-top:22px}

/* Day detail */
.modal{position:fixed;inset:0;background:rgba(0,0,0,0.65);display:flex;align-items:flex-end;justify-content:center;z-index:100;padding:0}
.modal.hidden{display:none}
.modal-card{background:var(--panel);border:1px solid var(--rule-strong);border-top-left-radius:16px;border-top-right-radius:16px;padding:18px 18px calc(22px + env(safe-area-inset-bottom,0px));width:100%;max-width:640px}
.modal-card strong{display:block;font-size:16px;font-weight:600;letter-spacing:-0.01em;margin-bottom:12px}
.modal-row{border-left:3px solid;border-radius:4px;background:var(--raised);padding:9px 12px;margin-top:8px}
.modal-name{display:block;font-size:14px;font-weight:500;text-wrap:pretty}
.modal-meta{display:block;font-family:var(--mono);font-variant-numeric:tabular-nums;font-size:11.5px;color:var(--ink-faint);margin-top:3px}
.modal-note{font-size:13px;color:var(--ink-muted);background:var(--raised);border-radius:6px;padding:9px 12px;margin-top:8px}
.modal-note.gap-note{background:var(--alert-wash);color:var(--alert)}
@media (min-width:560px){
  .modal{align-items:center;padding:24px}
  .modal-card{border-radius:16px;max-width:380px}
}
</style>
</head>
<body>
<div class="page-head"><h1>Coffee schedule</h1><span class="stamp">${escapeHtml(generatedAt)}</span></div>
${summaryHtml}
${months.map((m) => renderMonth(m, colorFor)).join("\n")}
${bagsHtml}
<div class="footer">Tap a day for what is brewing</div>
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
    // Push over HTTPS rather than SSH. The SSH key is passphrase-protected, so
    // publishing failed whenever ssh-agent had not been unlocked in that shell
    // session — which is most of the time for an unattended publish. gh's
    // credential helper authenticates from the gh token instead. It is passed
    // per-command via GIT_CONFIG_* so this neither depends on nor modifies the
    // machine's global git config.
    execSync(
      "git push --force https://github.com/mrmargolis/CoffeeScheduler.git HEAD:gh-pages",
      {
        cwd: tmpDir,
        stdio: "inherit",
        env: {
          ...process.env,
          GIT_CONFIG_COUNT: "1",
          GIT_CONFIG_KEY_0: "credential.helper",
          GIT_CONFIG_VALUE_0: "!gh auth git-credential",
        },
      }
    );
    console.log("Published to GitHub Pages!");
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}
