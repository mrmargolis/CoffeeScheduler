/**
 * Deterministic color assignment per roaster.
 * Uses a hash of the roaster name to pick from a palette.
 */
const FG = "#C9D1D9";

const PALETTE = [
  { bg: "#1c1a10", border: "#D29922", text: FG }, // amber
  { bg: "#10131e", border: "#58A6FF", text: FG }, // blue
  { bg: "#101a11", border: "#3FB950", text: FG }, // green
  { bg: "#1c1012", border: "#FF7B72", text: FG }, // pink
  { bg: "#14101c", border: "#BC8CFF", text: FG }, // purple
  { bg: "#1c1510", border: "#FFA657", text: FG }, // orange
  { bg: "#101c18", border: "#56D364", text: FG }, // teal
  { bg: "#101619", border: "#A5D6FF", text: FG }, // cyan
  { bg: "#12101c", border: "#D2A8FF", text: FG }, // indigo
  { bg: "#1c1010", border: "#F85149", text: FG }, // red
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
