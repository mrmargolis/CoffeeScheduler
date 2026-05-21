import type Database from "better-sqlite3";
import type { BeanWithComputed } from "./types";
import { addDays, today as getToday } from "./date-utils";
import { computeFrozenDays } from "./freeze-utils";

const BEAN_SELECT = `
  SELECT
    b.*,
    COALESCE(b.rest_days, rd.rest_days,
      CAST((SELECT value FROM settings WHERE key = 'default_rest_days') AS INTEGER)
    ) as effective_rest_days,
    COALESCE(
      (SELECT SUM(br.ground_coffee_grams) FROM brews br WHERE br.bean_id = b.id), 0
    ) as total_brewed_grams
  FROM beans b
  LEFT JOIN roaster_defaults rd ON rd.roaster = b.roaster`;

export function mapBeanRow(row: any, frozenDays: number = 0): BeanWithComputed {
  return {
    ...row,
    archived: Boolean(row.archived),
    is_frozen: Boolean(row.is_frozen),
    remaining_grams: row.weight_grams - row.total_brewed_grams,
    frozen_days: frozenDays,
    ready_date: row.roast_date
      ? addDays(row.roast_date, row.effective_rest_days + frozenDays)
      : null,
  };
}

export function queryBeans(
  db: Database.Database,
  opts: { archived?: boolean }
): BeanWithComputed[] {
  const frozenDaysMap = computeFrozenDays(db, getToday());
  return db
    .prepare(
      `${BEAN_SELECT}
    WHERE b.archived = ?
    ORDER BY
      CASE WHEN b.display_order IS NOT NULL THEN 0 ELSE 1 END,
      b.display_order,
      b.roast_date`
    )
    .all(opts.archived ? 1 : 0)
    .map((row: any) => mapBeanRow(row, frozenDaysMap.get(row.id) || 0));
}

export function queryBean(
  db: Database.Database,
  id: string
): BeanWithComputed | null {
  const row = db.prepare(`${BEAN_SELECT} WHERE b.id = ?`).get(id) as any;
  if (!row) return null;
  const frozenDaysMap = computeFrozenDays(db, getToday());
  return mapBeanRow(row, frozenDaysMap.get(id) || 0);
}

export function queryBeanRowsRaw(db: Database.Database): any[] {
  return db.prepare(BEAN_SELECT).all() as any[];
}
