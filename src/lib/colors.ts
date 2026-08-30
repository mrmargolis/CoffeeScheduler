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

function hashString(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash |= 0;
  }
  return Math.abs(hash);
}

export function getRoasterColor(roaster: string) {
  const index = hashString(roaster) % PALETTE.length;
  return PALETTE[index];
}
