import { describe, it, expect } from "vitest";
import { assignRoasterColors, getRoasterColor } from "@/lib/colors";

describe("getRoasterColor", () => {
  it("is stable for the same roaster", () => {
    expect(getRoasterColor("Square Mile")).toEqual(getRoasterColor("Square Mile"));
  });

  it("pairs a rail colour with its own tint and text", () => {
    const c = getRoasterColor("Square Mile");
    expect(c.border).toMatch(/^#[0-9a-f]{6}$/);
    expect(c.bg).toMatch(/^#[0-9a-f]{6}$/);
    expect(c.text).toMatch(/^#[0-9a-f]{6}$/);
  });
});

describe("assignRoasterColors", () => {
  it("separates roasters that hash to the same slot", () => {
    // These two collide under the plain hash.
    expect(getRoasterColor("Square Mile").border).toBe(
      getRoasterColor("La Cabra").border
    );

    const assigned = assignRoasterColors(["Square Mile", "La Cabra"]);
    expect(assigned.get("Square Mile")!.border).not.toBe(
      assigned.get("La Cabra")!.border
    );
  });

  it("leaves a roaster on its hashed colour when nothing else wants it", () => {
    const assigned = assignRoasterColors(["Square Mile"]);
    expect(assigned.get("Square Mile")).toEqual(getRoasterColor("Square Mile"));
  });

  it("gives ten roasters ten distinct colours", () => {
    const roasters = [
      "Square Mile", "La Cabra", "Coffee Collective", "Has Bean", "Friedhats",
      "Tim Wendelboe", "Origin", "Kiss the Hippo", "Assembly", "Workshop",
    ];
    const assigned = assignRoasterColors(roasters);
    const distinct = new Set([...assigned.values()].map((c) => c.border));
    expect(distinct.size).toBe(roasters.length);
  });

  it("is deterministic for the same ordered input", () => {
    const roasters = ["Square Mile", "La Cabra", "Friedhats"];
    expect(assignRoasterColors(roasters)).toEqual(assignRoasterColors(roasters));
  });

  it("still returns a colour for every roaster past the palette size", () => {
    const roasters = Array.from({ length: 14 }, (_, i) => `Roaster ${i}`);
    const assigned = assignRoasterColors(roasters);
    expect(assigned.size).toBe(14);
    for (const r of roasters) expect(assigned.get(r)!.border).toMatch(/^#/);
  });

  it("ignores a repeated roaster rather than reassigning it", () => {
    const assigned = assignRoasterColors(["Square Mile", "Square Mile"]);
    expect(assigned.size).toBe(1);
  });
});
