/**
 * Deterministic color assignment per roaster.
 * Uses a hash of the roaster name to pick from a palette.
 */
const PALETTE = [
  { bg: "#451a03", border: "#d97706", text: "#fdba74" }, // amber
  { bg: "#172554", border: "#3b82f6", text: "#93c5fd" }, // blue
  { bg: "#052e16", border: "#22c55e", text: "#86efac" }, // green
  { bg: "#500724", border: "#ec4899", text: "#f9a8d4" }, // pink
  { bg: "#1e1b4b", border: "#6366f1", text: "#a5b4fc" }, // indigo
  { bg: "#431407", border: "#f97316", text: "#fdba74" }, // orange
  { bg: "#3b0764", border: "#a855f7", text: "#d8b4fe" }, // purple
  { bg: "#042f2e", border: "#14b8a6", text: "#5eead4" }, // teal
  { bg: "#422006", border: "#eab308", text: "#fde047" }, // yellow
  { bg: "#450a0a", border: "#ef4444", text: "#fca5a5" }, // red
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
