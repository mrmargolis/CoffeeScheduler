import { NextRequest, NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import { autoThawBeans } from "@/lib/auto-thaw";
import { queryBeans } from "@/lib/bean-queries";
import { today as getToday } from "@/lib/date-utils";

export async function GET(request: NextRequest) {
  const db = getDb();
  const today = getToday();
  autoThawBeans(db, today);

  const showArchived =
    request.nextUrl.searchParams.get("archived") === "true";

  const beans = queryBeans(db, { archived: showArchived });

  return NextResponse.json(beans);
}
