import { addDays, dateRange } from "./date-utils";
import { ScheduleDay } from "./types";

/** Minimum viable dose. Beans with less than this remaining are done. */
const MIN_DOSE_GRAMS = 12;

/** Typical dose size used for rounding on transition days. */
const DOSE_SIZE_GRAMS = 15;

/** Minimum acceptable daily consumption. Days below this toss remnants. */
const MIN_DAILY_GRAMS = 39;

export interface SchedulerBean {
  id: string;
  name: string;
  roaster: string;
  roast_date: string | null;
  weight_grams: number;
  remaining_grams: number;
  effective_rest_days: number;
  is_frozen: boolean;
  planned_thaw_date: string | null;
  freeze_after_grams: number | null;
  display_order: number | null;
  frozen_days: number; // Total days spent frozen (computed from freeze_events)
}

export interface ActualBrew {
  bean_id: string;
  creation_date: string;
  ground_coffee_grams: number;
}

/**
 * Compute the ready date for a bean, accounting for frozen days.
 * Ready date = roast_date + effective_rest_days + frozen_days
 * (Frozen time doesn't count toward resting.)
 */
export function computeReadyDate(bean: SchedulerBean): string | null {
  if (!bean.roast_date) return null;
  return addDays(bean.roast_date, bean.effective_rest_days + bean.frozen_days);
}

/**
 * Sort beans by queue priority:
 * 1. Beans with display_order come first, sorted by display_order
 * 2. Then beans without display_order, sorted by ready_date (earliest first)
 * 3. Beans with no ready_date go last
 */
export function sortBeanQueue(beans: SchedulerBean[]): SchedulerBean[] {
  return [...beans].sort((a, b) => {
    const aHasOrder = a.display_order !== null;
    const bHasOrder = b.display_order !== null;

    if (aHasOrder && bHasOrder) {
      return a.display_order! - b.display_order!;
    }
    if (aHasOrder && !bHasOrder) return -1;
    if (!aHasOrder && bHasOrder) return 1;

    // Both lack display_order: in-progress beans (partially consumed) before untouched
    const aInProgress = a.remaining_grams < a.weight_grams;
    const bInProgress = b.remaining_grams < b.weight_grams;

    if (aInProgress && !bInProgress) return -1;
    if (!aInProgress && bInProgress) return 1;

    // Within same group, sort by ready_date
    const aReady = computeReadyDate(a);
    const bReady = computeReadyDate(b);

    if (aReady && bReady) return aReady.localeCompare(bReady);
    if (aReady && !bReady) return -1;
    if (!aReady && bReady) return 1;
    return 0;
  });
}

export interface DayOverride {
  dailyGrams: number;
  doseSize: number;
}

export interface ScheduleOptions {
  startDate: string;
  endDate: string;
  dailyConsumptionGrams: number;
  beans: SchedulerBean[];
  actualBrews: ActualBrew[];
  today: string;
  skipDays?: Set<string>;
  consumptionOverrides?: Map<string, DayOverride>;
}

/**
 * Aggregate multiple brews for the same bean on a single day into one consumption entry.
 */
/**
 * Aggregate multiple brews for the same bean on a single day into one consumption entry.
 * Does NOT deduct from remaining — remaining_grams already accounts for all historical brews.
 */
function aggregateBrews(
  dayBrews: ActualBrew[],
  beanMap: Map<string, SchedulerBean>,
): ScheduleDay["consumptions"] {
  const grouped = new Map<string, number>();
  for (const brew of dayBrews) {
    grouped.set(brew.bean_id, (grouped.get(brew.bean_id) || 0) + brew.ground_coffee_grams);
  }
  return Array.from(grouped, ([bean_id, grams]) => {
    const bean = beanMap.get(bean_id);
    return {
      bean_id,
      bean_name: bean?.name || "Unknown",
      roaster: bean?.roaster || "Unknown",
      grams,
    };
  });
}

export function computeSchedule(options: ScheduleOptions): ScheduleDay[] {
  const { startDate, endDate, dailyConsumptionGrams, beans, actualBrews, today, skipDays, consumptionOverrides } =
    options;

  // Build a map of actual brews by date
  const brewsByDate = new Map<string, ActualBrew[]>();
  for (const brew of actualBrews) {
    const existing = brewsByDate.get(brew.creation_date) || [];
    existing.push(brew);
    brewsByDate.set(brew.creation_date, existing);
  }

  // Filter to non-frozen (or frozen with planned thaw) beans with remaining grams
  const activeBeans = sortBeanQueue(
    beans.filter((b) => (!b.is_frozen || b.planned_thaw_date) && b.remaining_grams > MIN_DOSE_GRAMS)
  );

  // Track remaining grams per bean (mutable copy)
  const remaining = new Map<string, number>();
  for (const bean of activeBeans) {
    remaining.set(bean.id, bean.remaining_grams);
  }

  // Helper to look up bean info
  const beanMap = new Map(beans.map((b) => [b.id, b]));

  const days = dateRange(startDate, endDate);
  const schedule: ScheduleDay[] = [];

  for (const date of days) {
    const isPast = date < today;
    const isToday = date === today;

    // Check if this is a skip day (but actual brews override skips for past days)
    if (skipDays?.has(date)) {
      const dayBrews = brewsByDate.get(date) || [];
      if (isPast && dayBrews.length > 0) {
        // Past day with actual brews overrides skip
        const consumptions = aggregateBrews(dayBrews, beanMap);
        schedule.push({
          date,
          consumptions,
          is_gap: false,
          is_surplus: false,
          is_actual: true,
          is_skip: false,
        });
        continue;
      }

      // Skip day: no consumption, no deduction
      schedule.push({
        date,
        consumptions: [],
        is_gap: false,
        is_surplus: false,
        is_actual: false,
        is_skip: true,
      });
      continue;
    }

    // For past days, use actual brew data
    if (isPast || isToday) {
      const dayBrews = brewsByDate.get(date) || [];

      if (dayBrews.length > 0) {
        const consumptions = aggregateBrews(dayBrews, beanMap);

        schedule.push({
          date,
          consumptions,
          is_gap: false,
          is_surplus: false,
          is_actual: true,
          is_skip: false,
        });
        continue;
      }

      // Past day with no brews — show as gap if past, project if today
      if (isPast) {
        schedule.push({
          date,
          consumptions: [],
          is_gap: true,
          is_surplus: false,
          is_actual: true,
          is_skip: false,
        });
        continue;
      }
    }

    // Future days (or today with no brews): project consumption
    const dayOverride = consumptionOverrides?.get(date);
    const dayDailyGrams = dayOverride?.dailyGrams ?? dailyConsumptionGrams;
    const dayDoseSize = dayOverride?.doseSize ?? DOSE_SIZE_GRAMS;
    let gramsNeeded = dayDailyGrams;
    const consumptions: ScheduleDay["consumptions"] = [];

    // Incorporate pre-logged brews for future days (e.g. user entered
    // tomorrow's brew in advance). These count toward the daily target
    // and deduct from the bean's remaining supply.
    const futureBrews = brewsByDate.get(date) || [];
    const hasPreLogged = futureBrews.length > 0;
    if (hasPreLogged) {
      const preLogged = aggregateBrews(futureBrews, beanMap);
      for (const c of preLogged) {
        consumptions.push(c);
        const rem = remaining.get(c.bean_id) || 0;
        remaining.set(c.bean_id, Math.max(0, rem - c.grams));
        gramsNeeded -= c.grams;
      }
    }

    // Count how many beans are ready on this date
    let readyCount = 0;
    for (const bean of activeBeans) {
      const readyDate = computeReadyDate(bean);
      const rem = remaining.get(bean.id) || 0;
      if (readyDate && readyDate <= date && rem > MIN_DOSE_GRAMS) {
        // Skip bean if projected consumption has reached freeze-after target
        const freezeFloor = bean.freeze_after_grams != null
          ? bean.weight_grams - bean.freeze_after_grams
          : 0;
        if (rem - freezeFloor <= MIN_DOSE_GRAMS) continue;
        readyCount++;
      }
    }

    // Consume from queue in order
    const acceptableMin = dayOverride ? dayOverride.dailyGrams : MIN_DAILY_GRAMS;

    for (const bean of activeBeans) {
      if (gramsNeeded <= 0) break;
      // Don't start a new bean just to fill a gap smaller than a minimum dose
      if (consumptions.length > 0 && gramsNeeded <= MIN_DOSE_GRAMS) break;

      const readyDate = computeReadyDate(bean);
      if (!readyDate || readyDate > date) continue;

      const rem = remaining.get(bean.id) || 0;
      if (rem <= MIN_DOSE_GRAMS) continue;

      // Cap available grams to respect freeze-after target
      const freezeFloor = bean.freeze_after_grams != null
        ? bean.weight_grams - bean.freeze_after_grams
        : 0;
      const effectiveRem = rem - freezeFloor;

      // Skip bean if projected consumption has reached freeze-after target
      if (effectiveRem <= MIN_DOSE_GRAMS) continue;

      let consume = Math.min(gramsNeeded, effectiveRem);

      // If this bean can't fill the day, round down to a whole number of doses.
      // The sub-dose remainder is wasted (or frozen).
      if (consume < gramsNeeded) {
        const doses = Math.floor(consume / dayDoseSize);
        if (doses === 0) {
          // Can't even get one full dose — waste it, skip this bean
          remaining.set(bean.id, freezeFloor);
          continue;
        }
        const doseConsume = doses * dayDoseSize;
        remaining.set(bean.id, freezeFloor); // Rest is waste/frozen
        consume = doseConsume;
      } else {
        remaining.set(bean.id, rem - consume);
      }

      consumptions.push({
        bean_id: bean.id,
        bean_name: bean.name,
        roaster: bean.roaster,
        grams: consume,
      });
      gramsNeeded -= consume;
    }

    const totalConsumed = dayDailyGrams - gramsNeeded;

    // If we can't reach the acceptable minimum, toss the partial remnants
    // (remaining already decremented, so those grams are effectively wasted).
    // Skip this check when the user has pre-logged brews — they committed
    // to brewing on this day.
    if (!hasPreLogged && totalConsumed > 0 && totalConsumed < acceptableMin) {
      consumptions.length = 0;
      gramsNeeded = dayDailyGrams;
    }

    // Merge pre-logged and projected consumptions for the same bean
    // (e.g. 15g pre-logged WHG + 30g projected WHG → 45g WHG)
    if (hasPreLogged && consumptions.length > 1) {
      const merged = new Map<string, ScheduleDay["consumptions"][0]>();
      for (const c of consumptions) {
        const existing = merged.get(c.bean_id);
        if (existing) {
          existing.grams += c.grams;
        } else {
          merged.set(c.bean_id, { ...c });
        }
      }
      consumptions.length = 0;
      consumptions.push(...merged.values());
    }

    schedule.push({
      date,
      consumptions,
      is_gap: consumptions.length === 0 && gramsNeeded > 0,
      is_surplus: readyCount > 1,
      is_actual: false,
      is_skip: false,
    });
  }

  return schedule;
}
