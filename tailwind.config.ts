import type { Config } from "tailwindcss";

// Warm-graphite palette. These hexes are mirrored as CSS custom properties in
// src/app/globals.css for the FullCalendar overrides — keep the two in sync.
const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        canvas: "#141110",
        panel: "#1c1917",
        raised: "#241f1b",
        elevated: "#2b2621",
        rule: "#2c2723",
        "rule-strong": "#3d3833",
        track: "#322c26",

        ink: "#e9e6e0",
        "ink-muted": "#aea8a1",
        "ink-faint": "#807b74",

        accent: "#e5a152",
        "accent-dim": "#b67f40",
        "accent-wash": "#2e200f",
        "on-accent": "#211603",

        ok: "#91cb9c",
        "ok-wash": "#182a1c",
        rest: "#d3b48b",
        "rest-wash": "#2a231b",
        early: "#f3a677",
        "early-wash": "#331f14",
        cold: "#8ec2e6",
        "cold-wash": "#162733",
        "cold-line": "#2f4757",
        alert: "#ea8e82",
        "alert-wash": "#2f1b18",
      },
      fontFamily: {
        sans: ["var(--font-geist-sans)", "system-ui", "sans-serif"],
        mono: ["var(--font-geist-mono)", "ui-monospace", "monospace"],
      },
    },
  },
  plugins: [],
};
export default config;
