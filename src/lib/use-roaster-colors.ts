"use client";

import { useMemo } from "react";
import useSWR from "swr";
import { assignRoasterColors, getRoasterColor, RoasterColor } from "./colors";
import { BeanWithComputed } from "./types";

const fetcher = (url: string) => fetch(url).then((r) => r.json());

/**
 * Colours for the roasters currently in the collection, assigned so no two of
 * them collide. Reads the same `/api/beans` list every view already fetches, so
 * it costs nothing extra and every surface agrees — and matches the published
 * schedule page, which assigns over the same set.
 *
 * Falls back to the plain per-name hash for a roaster that is not in the list
 * (an archived bag, or a per-roaster rest default with no bags left).
 */
export function useRoasterColors(): (roaster: string) => RoasterColor {
  const { data: beans } = useSWR<BeanWithComputed[]>("/api/beans", fetcher);

  return useMemo(() => {
    const assigned = assignRoasterColors((beans ?? []).map((b) => b.roaster));
    return (roaster: string) =>
      assigned.get(roaster) ?? getRoasterColor(roaster);
  }, [beans]);
}
