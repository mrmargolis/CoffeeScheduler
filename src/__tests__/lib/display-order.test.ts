import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";
import { resequenceDisplayOrder } from "@/lib/display-order";

describe("resequenceDisplayOrder", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
    initializeSchema(db);

    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, display_order)
       VALUES ('a', 'A', 'R', '2026-01-01', 250, 1)`
    ).run();
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, display_order)
       VALUES ('b', 'B', 'R', '2026-01-02', 250, 3)`
    ).run();
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, display_order)
       VALUES ('c', 'C', 'R', '2026-01-03', 250, 5)`
    ).run();
  });

  it("closes gaps to produce sequential 1,2,3", () => {
    resequenceDisplayOrder(db);

    const rows = db
      .prepare("SELECT id, display_order FROM beans ORDER BY display_order")
      .all() as { id: string; display_order: number }[];

    expect(rows).toEqual([
      { id: "a", display_order: 1 },
      { id: "b", display_order: 2 },
      { id: "c", display_order: 3 },
    ]);
  });

  it("skips beans with NULL display_order", () => {
    db.prepare("UPDATE beans SET display_order = NULL WHERE id = 'b'").run();

    resequenceDisplayOrder(db);

    const rows = db
      .prepare("SELECT id, display_order FROM beans ORDER BY id")
      .all() as { id: string; display_order: number | null }[];

    expect(rows).toEqual([
      { id: "a", display_order: 1 },
      { id: "b", display_order: null },
      { id: "c", display_order: 2 },
    ]);
  });

  it("is a no-op when no beans have display_order", () => {
    db.prepare("UPDATE beans SET display_order = NULL").run();

    resequenceDisplayOrder(db);

    const rows = db
      .prepare("SELECT display_order FROM beans")
      .all() as { display_order: number | null }[];

    expect(rows.every((r) => r.display_order === null)).toBe(true);
  });
});
