import AdmZip from "adm-zip";

export interface RawBean {
  id: string;
  name: string;
  roaster: string;
  roast_date: string | null;
  weight_grams: number;
  cost: number | null;
  flavour_profile: string | null;
  country: string | null;
  region: string | null;
  variety: string | null;
  processing: string | null;
  archived: boolean;
  is_frozen: boolean;
}

export interface RawBrew {
  bean_id: string;
  ground_coffee_grams: number;
  creation_date: string;
  bean_age_days: number | null;
  rating: number | null;
}

export interface FreezeInfo {
  bean_id: string;
  frozen_date: string;
}

export interface ParseResult {
  beans: RawBean[];
  brews: RawBrew[];
  freezeEvents: FreezeInfo[];
  errors: string[];
}

/**
 * Extract YYYY-MM-DD from an ISO 8601 date string (e.g. "2024-06-15T21:26:00.000Z").
 * Returns null for empty/invalid strings.
 */
function parseIsoDate(dateStr: string | undefined | null): string | null {
  if (!dateStr) return null;
  const match = dateStr.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!match) return null;
  const [, year, month, day] = match;
  const m = parseInt(month, 10);
  const d = parseInt(day, 10);
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return `${year}-${month}-${day}`;
}

/**
 * Convert unix timestamp (seconds) to YYYY-MM-DD.
 */
function unixToDate(ts: number): string | null {
  if (!ts || !isFinite(ts)) return null;
  const d = new Date(ts * 1000);
  return d.toISOString().split("T")[0];
}

/**
 * Calculate days between two ISO date strings (end - start).
 */
function daysDiff(startIso: string, endIso: string): number {
  const start = new Date(startIso + "T00:00:00Z");
  const end = new Date(endIso + "T00:00:00Z");
  return Math.round((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
}

export function parseBcZip(buffer: Buffer): ParseResult {
  const errors: string[] = [];
  const zip = new AdmZip(buffer);

  // Read main JSON
  const mainEntry = zip.getEntry("Beanconqueror.json");
  if (!mainEntry) {
    return { beans: [], brews: [], freezeEvents: [], errors: ["No Beanconqueror.json found in ZIP"] };
  }

  let mainData: any;
  try {
    mainData = JSON.parse(mainEntry.getData().toString("utf-8"));
  } catch {
    return { beans: [], brews: [], freezeEvents: [], errors: ["Failed to parse Beanconqueror.json"] };
  }

  // Parse beans
  const rawBeans: any[] = mainData.BEANS ?? [];
  const beans: RawBean[] = [];
  const freezeEvents: FreezeInfo[] = [];
  const beanRoastDates = new Map<string, string>();

  for (let i = 0; i < rawBeans.length; i++) {
    const b = rawBeans[i];
    const id = b.config?.uuid;
    if (!id) {
      errors.push(`Bean index ${i}: missing config.uuid, skipping`);
      continue;
    }

    const roastDate = parseIsoDate(b.roastingDate);
    if (roastDate) {
      beanRoastDates.set(id, roastDate);
    }

    const cost = typeof b.cost === "number" && b.cost !== 0 ? b.cost : null;
    const beanInfo = Array.isArray(b.bean_information) && b.bean_information.length > 0
      ? b.bean_information[0]
      : null;

    const frozenId = b.frozenId || "";
    const unfrozenDate = b.unfrozenDate || "";
    const isFrozen = !!frozenId && !unfrozenDate;

    beans.push({
      id,
      name: b.name ?? "",
      roaster: b.roaster ?? "",
      roast_date: roastDate,
      weight_grams: typeof b.weight === "number" ? b.weight : 0,
      cost,
      flavour_profile: b.aromatics || null,
      country: beanInfo?.country || null,
      region: beanInfo?.region || null,
      variety: beanInfo?.variety || null,
      processing: beanInfo?.processing || null,
      archived: !!b.finished,
      is_frozen: isFrozen,
    });

    // Create freeze event for currently frozen beans
    if (isFrozen) {
      const frozenDate = parseIsoDate(b.frozenDate);
      if (frozenDate) {
        freezeEvents.push({ bean_id: id, frozen_date: frozenDate });
      }
    }
  }

  // Collect all brews: main file + split files
  const allRawBrews: any[] = [...(mainData.BREWS ?? [])];
  const seenBrewIds = new Set<string>();

  // Add brews from split files
  const entries = zip.getEntries();
  for (const entry of entries) {
    if (entry.entryName.match(/^Beanconqueror_Brews_\d+\.json$/)) {
      try {
        const splitBrews = JSON.parse(entry.getData().toString("utf-8"));
        if (Array.isArray(splitBrews)) {
          allRawBrews.push(...splitBrews);
        }
      } catch {
        errors.push(`Failed to parse ${entry.entryName}`);
      }
    }
  }

  // Parse brews, deduplicating by config.uuid
  const brews: RawBrew[] = [];
  for (let i = 0; i < allRawBrews.length; i++) {
    const br = allRawBrews[i];
    const brewId = br.config?.uuid;
    if (brewId) {
      if (seenBrewIds.has(brewId)) continue;
      seenBrewIds.add(brewId);
    }

    const beanId = br.bean;
    if (!beanId) {
      errors.push(`Brew index ${i}: missing bean reference, skipping`);
      continue;
    }

    const unixTs = br.config?.unix_timestamp;
    const creationDate = unixToDate(unixTs);
    if (!creationDate) {
      errors.push(`Brew index ${i}: invalid creation date, skipping`);
      continue;
    }

    const grindWeight = typeof br.grind_weight === "number" ? br.grind_weight : 0;
    const rating = typeof br.rating === "number" && br.rating !== 0 ? br.rating : null;

    // Calculate bean age
    const roastDate = beanRoastDates.get(beanId);
    const beanAgeDays = roastDate ? daysDiff(roastDate, creationDate) : null;

    brews.push({
      bean_id: beanId,
      ground_coffee_grams: grindWeight,
      creation_date: creationDate,
      bean_age_days: beanAgeDays,
      rating,
    });
  }

  return { beans, brews, freezeEvents, errors };
}
