/**
 * Deterministic color assignment per roaster.
 * Uses a hash of the roaster name to pick from a palette.
 *
 * Each entry is one hue at a shared lightness and chroma, so no roaster shouts
 * louder than another: `border` is the 5px rail on a calendar bar and the dot
 * in the backlog, `bg` the tint behind the bar, `text` the label on that tint.
 * Palette order is load-bearing — changing it reshuffles every roaster's color.
 */
const PALETTE = [
  { bg: "#2d2114", border: "#e1b581", text: "#efdcc4" }, // amber
  { bg: "#172632", border: "#8fc4f1", text: "#d5e5f3" }, // blue
  { bg: "#19281c", border: "#96cea1", text: "#d8ecdc" }, // green
  { bg: "#311e1f", border: "#efa8ac", text: "#f4dcde" }, // rose
  { bg: "#262131", border: "#c6b2ed", text: "#e5ddf6" }, // violet
  { bg: "#301f18", border: "#edad90", text: "#f3ded3" }, // orange
  { bg: "#112927", border: "#78d0ca", text: "#cdeeeb" }, // teal
  { bg: "#12272e", border: "#7ccbe4", text: "#cfebf3" }, // cyan
  { bg: "#202333", border: "#adbaf5", text: "#dee3fa" }, // indigo
  { bg: "#311e1d", border: "#f0a9a2", text: "#f5dcda" }, // red
];

// Coprime with PALETTE.length, so probing visits every slot; large enough to
// jump to a clearly different hue rather than the adjacent one.
const PROBE_STRIDE = 3;

function hashString(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash |= 0;
  }
  return Math.abs(hash);
}

export interface RoasterColor {
  bg: string;
  border: string;
  text: string;
}

/** Look up one roaster's colour, independent of who else is on screen. */
export function getRoasterColor(roaster: string): RoasterColor {
  const index = hashString(roaster) % PALETTE.length;
  return PALETTE[index];
}

/**
 * Assign colours across a known set of roasters so no two of them collide.
 *
 * Hashing alone puts roasters in the same slot often enough to matter — with
 * ten slots, two roasters share a colour surprisingly quickly. That is
 * survivable where the colour sits beside a label, but not where colour is the
 * only thing identifying a bag, as on the published schedule page.
 *
 * Each roaster keeps its hashed slot when that slot is free. When it is not,
 * probing steps by PROBE_STRIDE rather than by one: neighbouring palette
 * entries are neighbouring hues (teal sits next to cyan), so a +1 probe would
 * hand out two colours nobody can tell apart. The stride is coprime with the
 * palette length, so it still reaches every slot. Deterministic for a given
 * ordered set. Beyond ten roasters collisions return, since the palette runs
 * out.
 */
export function assignRoasterColors(
  roasters: string[]
): Map<string, RoasterColor> {
  const taken = new Set<number>();
  const assigned = new Map<string, RoasterColor>();

  for (const roaster of roasters) {
    if (assigned.has(roaster)) continue;
    const preferred = hashString(roaster) % PALETTE.length;
    let slot = preferred;
    for (let probe = 0; probe < PALETTE.length; probe++) {
      const candidate = (preferred + probe * PROBE_STRIDE) % PALETTE.length;
      if (!taken.has(candidate)) {
        slot = candidate;
        break;
      }
    }
    taken.add(slot);
    assigned.set(roaster, PALETTE[slot]);
  }

  return assigned;
}
