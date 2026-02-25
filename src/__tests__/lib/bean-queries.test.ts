import { describe, it, expect, beforeEach } from "vitest";
import Database from "better-sqlite3";
import { initializeSchema } from "@/lib/schema";
import { queryBeans, queryBean, queryBeanRowsRaw, mapBeanRow } from "@/lib/bean-queries";

describe("bean-queries", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.pragma("foreign_keys = ON");
    initializeSchema(db);

    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived)
       VALUES ('bean-1', 'Ethiopia', 'Square Mile', '2026-01-15', 250, 0)`
    ).run();
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived)
       VALUES ('bean-2', 'Colombia', 'Tim Wendelboe', '2026-01-20', 250, 0)`
    ).run();
    db.prepare(
      `INSERT INTO beans (id, name, roaster, roast_date, weight_grams, archived)
       VALUES ('bean-3', 'Brazil', 'Local', '2025-06-01', 250, 1)`
    ).run();
  });

  describe("queryBeans", () => {
    it("returns active beans with computed fields", () => {
      db.prepare(
        "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('bean-1', 15, '2026-02-15')"
      ).run();
      db.prepare(
        "INSERT INTO brews (bean_id, ground_coffee_grams, creation_date) VALUES ('bean-1', 15, '2026-02-16')"
      ).run();

      const beans = queryBeans(db, { archived: false });

      expect(beans).toHaveLength(2);
      const eth = beans.find((b) => b.id === "bean-1")!;
      expect(eth.total_brewed_grams).toBe(30);
      expect(eth.remaining_grams).toBe(220);
      expect(eth.archived).toBe(false);
      expect(eth.is_frozen).toBe(false);
      expect(eth.effective_rest_days).toBe(30);
      // ready_date = roast_date + 30 days = 2026-02-14
      expect(eth.ready_date).toBe("2026-02-14");
    });

    it("returns archived beans when requested", () => {
      const active = queryBeans(db, { archived: false });
      const archived = queryBeans(db, { archived: true });

      expect(active).toHaveLength(2);
      expect(archived).toHaveLength(1);
      expect(archived[0].id).toBe("bean-3");
      expect(archived[0].archived).toBe(true);
    });

    it("orders by display_order then roast_date", () => {
      db.prepare("UPDATE beans SET display_order = 2 WHERE id = 'bean-1'").run();
      db.prepare("UPDATE beans SET display_order = 1 WHERE id = 'bean-2'").run();

      const beans = queryBeans(db, { archived: false });

      expect(beans[0].id).toBe("bean-2");
      expect(beans[1].id).toBe("bean-1");
    });
  });

  describe("queryBean", () => {
    it("returns single bean with computed fields", () => {
      const bean = queryBean(db, "bean-1");

      expect(bean).not.toBeNull();
      expect(bean!.name).toBe("Ethiopia");
      expect(bean!.remaining_grams).toBe(250);
      expect(bean!.effective_rest_days).toBe(30);
      expect(bean!.ready_date).toBe("2026-02-14");
    });

    it("returns null for missing ID", () => {
      const bean = queryBean(db, "nonexistent");
      expect(bean).toBeNull();
    });
  });

  describe("queryBeanRowsRaw", () => {
    it("returns raw rows without boolean conversion or ready_date", () => {
      const rows = queryBeanRowsRaw(db);

      expect(rows.length).toBe(3); // includes archived
      const eth = rows.find((r: any) => r.id === "bean-1")!;
      // Raw rows have SQLite integer booleans, not JS booleans
      expect(eth.archived).toBe(0);
      expect(eth.is_frozen).toBe(0);
      expect(eth.ready_date).toBeUndefined();
    });
  });

  describe("mapBeanRow", () => {
    it("computes ready_date correctly", () => {
      const row = {
        roast_date: "2026-01-15",
        effective_rest_days: 30,
        weight_grams: 250,
        total_brewed_grams: 50,
        archived: 1,
        is_frozen: 0,
      };

      const mapped = mapBeanRow(row);

      expect(mapped.ready_date).toBe("2026-02-14");
      expect(mapped.remaining_grams).toBe(200);
      expect(mapped.archived).toBe(true);
      expect(mapped.is_frozen).toBe(false);
    });

    it("handles null roast_date", () => {
      const row = {
        roast_date: null,
        effective_rest_days: 30,
        weight_grams: 250,
        total_brewed_grams: 0,
        archived: 0,
        is_frozen: 0,
      };

      const mapped = mapBeanRow(row);
      expect(mapped.ready_date).toBeNull();
    });
  });

  describe("effective rest days fallback chain", () => {
    it("falls back from bean override to roaster default to global setting", () => {
      // No bean override, no roaster default → global default (30)
      let bean = queryBean(db, "bean-1")!;
      expect(bean.effective_rest_days).toBe(30);

      // Add roaster default → roaster default (28)
      db.prepare(
        "INSERT INTO roaster_defaults (roaster, rest_days) VALUES ('Square Mile', 28)"
      ).run();
      bean = queryBean(db, "bean-1")!;
      expect(bean.effective_rest_days).toBe(28);

      // Bean override takes precedence (14)
      db.prepare("UPDATE beans SET rest_days = 14 WHERE id = 'bean-1'").run();
      bean = queryBean(db, "bean-1")!;
      expect(bean.effective_rest_days).toBe(14);
    });
  });
});
