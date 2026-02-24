/**
 * Deterministic color assignment per roaster.
 * Uses a hash of the roaster name to pick from a palette.
 */
const PALETTE = [
  { bg: "#fef3c7", border: "#d97706", text: "#92400e" }, // amber
  { bg: "#dbeafe", border: "#2563eb", text: "#1e40af" }, // blue
  { bg: "#dcfce7", border: "#16a34a", text: "#166534" }, // green
  { bg: "#fce7f3", border: "#db2777", text: "#9d174d" }, // pink
  { bg: "#e0e7ff", border: "#4f46e5", text: "#3730a3" }, // indigo
  { bg: "#ffedd5", border: "#ea580c", text: "#9a3412" }, // orange
  { bg: "#f3e8ff", border: "#9333ea", text: "#6b21a8" }, // purple
  { bg: "#ccfbf1", border: "#0d9488", text: "#115e59" }, // teal
  { bg: "#fef9c3", border: "#ca8a04", text: "#854d0e" }, // yellow
  { bg: "#fee2e2", border: "#dc2626", text: "#991b1b" }, // red
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
