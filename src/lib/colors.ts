/**
 * Deterministic color assignment per roaster.
 * Uses a hash of the roaster name to pick from a palette.
 */
const PALETTE = [
  { bg: "#2a2017", border: "#e0af68", text: "#e0af68" }, // amber
  { bg: "#1a2030", border: "#7aa2f7", text: "#7aa2f7" }, // blue
  { bg: "#1a2617", border: "#9ece6a", text: "#9ece6a" }, // green
  { bg: "#2a1a24", border: "#f7768e", text: "#f7768e" }, // pink
  { bg: "#1e1a30", border: "#bb9af7", text: "#bb9af7" }, // indigo
  { bg: "#2a1e17", border: "#ff9e64", text: "#ff9e64" }, // orange
  { bg: "#221a2e", border: "#9d7cd8", text: "#9d7cd8" }, // purple
  { bg: "#172624", border: "#73daca", text: "#73daca" }, // teal
  { bg: "#1a2530", border: "#7dcfff", text: "#7dcfff" }, // cyan
  { bg: "#2a1a1a", border: "#ff7b72", text: "#ff7b72" }, // red
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
