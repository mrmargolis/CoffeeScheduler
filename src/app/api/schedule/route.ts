import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import { today as getToday } from "@/lib/date-utils";
import { autoThawBeans } from "@/lib/auto-thaw";
import { autoFreezeBeans } from "@/lib/auto-freeze";
import { loadScheduleData } from "@/lib/schedule-loader";

export async function GET(request: NextRequest) {
  const db = getDb();
  const params = request.nextUrl.searchParams;

  const today = getToday();

  // Auto-thaw beans whose planned thaw date has arrived
  autoThawBeans(db, today);
  autoFreezeBeans(db, today);

  const startDate = params.get("start") || today;
  const endDate =
    params.get("end") ||
    (() => {
      const d = new Date();
      d.setMonth(d.getMonth() + 3);
      return d.toISOString().split("T")[0];
    })();

  const { schedule } = loadScheduleData(db, startDate, endDate, today);

  return NextResponse.json(schedule);
}
