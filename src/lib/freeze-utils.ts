import type Database from "better-sqlite3";
import { daysBetween } from "./date-utils";

/**
 * Effective age = calendar days since roast minus days spent frozen.
 * Frozen time doesn't age the bean.
 *
 * Returns 0 if roastDate is null. Floored at 0 to guard against drift
 * between today and the planned-thaw projection.
 */
export function effectiveAge(
  roastDate: string | null,
  asOfDate: string,
  frozenDays: number
): number | null {
  if (!roastDate) return null;
  return Math.max(0, daysBetween(roastDate, asOfDate) - frozenDays);
}

/**
 * Compute total days each bean has spent frozen, derived from freeze_events.
 *
 * For balanced freeze→thaw pairs, sums (thaw - freeze).
 * For a still-active freeze (no matching thaw), counts up to the bean's
 * planned_thaw_date if set, otherwise up to `today`.
 */
export function computeFrozenDays(
  db: Database.Database,
  today: string
): Map<string, number> {
  const events = db
    .prepare(
      "SELECT bean_id, event_type, event_date FROM freeze_events ORDER BY event_date"
    )
    .all() as { bean_id: string; event_type: string; event_date: string }[];

  const frozenDays = new Map<string, number>();
  const activeFreezeStart = new Map<string, string>();

  for (const event of events) {
    if (event.event_type === "freeze") {
      activeFreezeStart.set(event.bean_id, event.event_date);
    } else if (event.event_type === "thaw") {
      const start = activeFreezeStart.get(event.bean_id);
      if (start) {
        const days = daysBetween(start, event.event_date);
        frozenDays.set(event.bean_id, (frozenDays.get(event.bean_id) || 0) + days);
        activeFreezeStart.delete(event.bean_id);
      }
    }
  }

  if (activeFreezeStart.size > 0) {
    const plannedThawRows = db
      .prepare(
        "SELECT id, planned_thaw_date FROM beans WHERE id IN (" +
          Array.from(activeFreezeStart.keys()).map(() => "?").join(",") +
          ")"
      )
      .all(...activeFreezeStart.keys()) as {
      id: string;
      planned_thaw_date: string | null;
    }[];

    const plannedThaw = new Map(
      plannedThawRows.map((r) => [r.id, r.planned_thaw_date])
    );

    for (const [beanId, freezeStart] of activeFreezeStart) {
      const end = plannedThaw.get(beanId) || today;
      const days = daysBetween(freezeStart, end);
      frozenDays.set(beanId, (frozenDays.get(beanId) || 0) + days);
    }
  }

  return frozenDays;
}
