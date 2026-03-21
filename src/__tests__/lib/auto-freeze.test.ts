import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";
import { autoFreezeBeans } from "@/lib/auto-freeze";

describe("autoFreezeBeans", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
    initializeSchema(db);
  });

  it("clears display_order and resequences remaining beans", () => {
    // Three beans with sequential display_order, middle one near its freeze threshold
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, display_order, freeze_after_grams)
       VALUES ('a', 'A', 'R', '2026-01-01', 250, 1, NULL)`
    ).run();
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, display_order, freeze_after_grams)
       VALUES ('b', 'B', 'R', '2026-01-02', 250, 2, 20)`
    ).run();
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, display_order, freeze_after_grams)
       VALUES ('c', 'C', 'R', '2026-01-03', 250, 3, NULL)`
    ).run();

    // Bean B has brewed 15g; 15 + 12 >= 20, so it should auto-freeze
    db.prepare(
      "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('b', 15, '2026-02-01')"
    ).run();

    autoFreezeBeans(db, "2026-02-02");

    // Bean B should be frozen with NULL display_order
    const beanB = db
      .prepare("SELECT is_frozen, display_order FROM beans WHERE id = 'b'")
      .get() as { is_frozen: number; display_order: number | null };
    expect(beanB.is_frozen).toBe(1);
    expect(beanB.display_order).toBeNull();

    // Remaining beans should be resequenced: 1, 2 (no gap)
    const remaining = db
      .prepare(
        "SELECT id, display_order FROM beans WHERE display_order IS NOT NULL ORDER BY display_order"
      )
      .all() as { id: string; display_order: number }[];
    expect(remaining).toEqual([
      { id: "a", display_order: 1 },
      { id: "c", display_order: 2 },
    ]);
  });
});
