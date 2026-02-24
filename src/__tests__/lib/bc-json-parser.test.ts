import { describe, it, expect } from "vitest";
import AdmZip from "adm-zip";
import { parseBcZip } from "@/lib/bc-json-parser";

function createTestZip(
  beans: any[] = [],
  brews: any[] = [],
  extraBrewFiles?: Record<string, any[]>
): Buffer {
  const zip = new AdmZip();

  const mainData: any = { BEANS: beans, BREWS: brews };
  zip.addFile("Beanconqueror.json", Buffer.from(JSON.stringify(mainData)));

  if (extraBrewFiles) {
    for (const [name, data] of Object.entries(extraBrewFiles)) {
      zip.addFile(name, Buffer.from(JSON.stringify(data)));
    }
  }

  return zip.toBuffer();
}

function makeBean(overrides: Record<string, any> = {}) {
  return {
    name: "Test Bean",
    roaster: "Test Roaster",
    roastingDate: "2026-01-15T00:00:00.000Z",
    weight: 250,
    cost: 16.5,
    aromatics: "Floral, Citrus",
    finished: false,
    bean_information: [
      {
        country: "Ethiopia",
        region: "Yirgacheffe",
        variety: "Heirloom",
        processing: "Washed",
      },
    ],
    config: { uuid: "uuid-1", unix_timestamp: 1700000000 },
    ...overrides,
  };
}

function makeBrew(overrides: Record<string, any> = {}) {
  return {
    bean: "uuid-1",
    grind_weight: 15,
    rating: 4,
    config: { uuid: "brew-1", unix_timestamp: 1706745600 }, // 2024-02-01
    ...overrides,
  };
}

describe("parseBcZip", () => {
  it("parses beans with all fields", () => {
    const buffer = createTestZip([makeBean()]);

    const result = parseBcZip(buffer);
    expect(result.beans).toHaveLength(1);
    expect(result.beans[0]).toEqual({
      id: "uuid-1",
      name: "Test Bean",
      roaster: "Test Roaster",
      roast_date: "2026-01-15",
      weight_grams: 250,
      cost: 16.5,
      flavour_profile: "Floral, Citrus",
      country: "Ethiopia",
      region: "Yirgacheffe",
      variety: "Heirloom",
      processing: "Washed",
      archived: false,
      is_frozen: false,
    });
    expect(result.freezeEvents).toHaveLength(0);
  });

  it("parses frozen beans (frozenId set, unfrozenDate empty)", () => {
    const buffer = createTestZip([
      makeBean({
        frozenId: "abc123",
        frozenDate: "2026-01-20T10:00:00.000Z",
        unfrozenDate: "",
      }),
    ]);

    const result = parseBcZip(buffer);
    expect(result.beans[0].is_frozen).toBe(true);
    expect(result.freezeEvents).toHaveLength(1);
    expect(result.freezeEvents[0]).toEqual({
      bean_id: "uuid-1",
      frozen_date: "2026-01-20",
    });
  });

  it("parses thawed beans (frozenId set, unfrozenDate set) as not frozen", () => {
    const buffer = createTestZip([
      makeBean({
        frozenId: "abc123",
        frozenDate: "2026-01-20T10:00:00.000Z",
        unfrozenDate: "2026-02-01T10:00:00.000Z",
      }),
    ]);

    const result = parseBcZip(buffer);
    expect(result.beans[0].is_frozen).toBe(false);
    expect(result.freezeEvents).toHaveLength(0);
  });

  it("parses brews from main file", () => {
    const bean = makeBean();
    const brew = makeBrew();
    const buffer = createTestZip([bean], [brew]);

    const result = parseBcZip(buffer);
    expect(result.brews).toHaveLength(1);
    expect(result.brews[0]).toEqual({
      bean_id: "uuid-1",
      ground_coffee_grams: 15,
      creation_date: "2024-02-01",
      bean_age_days: expect.any(Number),
      rating: 4,
    });
  });

  it("combines brews from main file and split files", () => {
    const bean = makeBean();
    const mainBrew = makeBrew({
      config: { uuid: "brew-main", unix_timestamp: 1706745600 },
    });
    const splitBrew1 = makeBrew({
      config: { uuid: "brew-split-1", unix_timestamp: 1706832000 },
    });
    const splitBrew2 = makeBrew({
      config: { uuid: "brew-split-2", unix_timestamp: 1706918400 },
    });

    const buffer = createTestZip([bean], [mainBrew], {
      "Beanconqueror_Brews_1.json": [splitBrew1],
      "Beanconqueror_Brews_2.json": [splitBrew2],
    });

    const result = parseBcZip(buffer);
    expect(result.brews).toHaveLength(3);
  });

  it("deduplicates brews by config.uuid", () => {
    const bean = makeBean();
    const brew = makeBrew({
      config: { uuid: "same-uuid", unix_timestamp: 1706745600 },
    });

    const buffer = createTestZip([bean], [brew], {
      "Beanconqueror_Brews_1.json": [brew],
    });

    const result = parseBcZip(buffer);
    expect(result.brews).toHaveLength(1);
  });

  it("handles missing optional fields gracefully", () => {
    const buffer = createTestZip([
      {
        name: "Minimal Bean",
        roaster: "R",
        config: { uuid: "uuid-min", unix_timestamp: 1700000000 },
        weight: 200,
      },
    ]);

    const result = parseBcZip(buffer);
    expect(result.beans[0].cost).toBeNull();
    expect(result.beans[0].flavour_profile).toBeNull();
    expect(result.beans[0].country).toBeNull();
    expect(result.beans[0].region).toBeNull();
    expect(result.beans[0].variety).toBeNull();
    expect(result.beans[0].processing).toBeNull();
    expect(result.beans[0].roast_date).toBeNull();
  });

  it("treats cost of 0 as null", () => {
    const buffer = createTestZip([makeBean({ cost: 0 })]);
    const result = parseBcZip(buffer);
    expect(result.beans[0].cost).toBeNull();
  });

  it("treats rating of 0 as null", () => {
    const buffer = createTestZip(
      [makeBean()],
      [makeBrew({ rating: 0 })]
    );
    const result = parseBcZip(buffer);
    expect(result.brews[0].rating).toBeNull();
  });

  it("skips beans without config.uuid", () => {
    const buffer = createTestZip([{ name: "Bad Bean" }]);
    const result = parseBcZip(buffer);
    expect(result.beans).toHaveLength(0);
    expect(result.errors).toHaveLength(1);
    expect(result.errors[0]).toContain("missing config.uuid");
  });

  it("skips brews with invalid creation date", () => {
    const buffer = createTestZip(
      [makeBean()],
      [{ bean: "uuid-1", grind_weight: 15, config: { uuid: "b-1" } }]
    );
    const result = parseBcZip(buffer);
    expect(result.brews).toHaveLength(0);
    expect(result.errors.some((e) => e.includes("invalid creation date"))).toBe(true);
  });

  it("calculates bean_age_days from roast date and brew date", () => {
    const bean = makeBean({
      roastingDate: "2026-01-01T00:00:00.000Z",
    });
    // unix_timestamp for 2026-01-15 00:00:00 UTC = 1768435200
    const brew = makeBrew({
      config: { uuid: "brew-age", unix_timestamp: 1768435200 },
    });

    const buffer = createTestZip([bean], [brew]);
    const result = parseBcZip(buffer);
    expect(result.brews[0].bean_age_days).toBe(14);
  });

  it("returns null bean_age_days when roast date is missing", () => {
    const bean = makeBean({ roastingDate: "" });
    const brew = makeBrew();
    const buffer = createTestZip([bean], [brew]);
    const result = parseBcZip(buffer);
    expect(result.brews[0].bean_age_days).toBeNull();
  });

  it("returns error when ZIP has no Beanconqueror.json", () => {
    const zip = new AdmZip();
    zip.addFile("other.json", Buffer.from("{}"));
    const result = parseBcZip(zip.toBuffer());
    expect(result.beans).toHaveLength(0);
    expect(result.errors[0]).toContain("No Beanconqueror.json");
  });

  it("parses multiple beans and brews", () => {
    const beans = [
      makeBean({ config: { uuid: "b1", unix_timestamp: 1700000000 } }),
      makeBean({
        name: "Bean 2",
        config: { uuid: "b2", unix_timestamp: 1700000001 },
      }),
    ];
    const brews = [
      makeBrew({ bean: "b1", config: { uuid: "br1", unix_timestamp: 1706745600 } }),
      makeBrew({ bean: "b1", config: { uuid: "br2", unix_timestamp: 1706832000 } }),
      makeBrew({ bean: "b2", config: { uuid: "br3", unix_timestamp: 1706918400 } }),
    ];

    const buffer = createTestZip(beans, brews);
    const result = parseBcZip(buffer);
    expect(result.beans).toHaveLength(2);
    expect(result.brews).toHaveLength(3);
    expect(result.errors).toHaveLength(0);
  });
});
