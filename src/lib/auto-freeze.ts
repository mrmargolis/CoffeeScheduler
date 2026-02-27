import Database from "better-sqlite3";

/**
 * Auto-freeze beans whose brewed grams have reached the freeze_after_grams target.
 * Sets is_frozen = 1, clears freeze_after_grams, and inserts a freeze event.
 */
export function autoFreezeBeans(db: Database.Database, today: string): void {
  const beansToFreeze = db
    .prepare(
      `SELECT b.id FROM beans b
       WHERE b.is_frozen = 0
         AND b.freeze_after_grams IS NOT NULL
         AND (SELECT COALESCE(SUM(br.ground_coffee_grams), 0) FROM brews br WHERE br.bean_id = b.id) + 12 >= b.freeze_after_grams`
    )
    .all() as { id: string }[];

  if (beansToFreeze.length === 0) return;

  const freezeTx = db.transaction(() => {
    for (const bean of beansToFreeze) {
      db.prepare(
        "UPDATE beans SET is_frozen = 1, freeze_after_grams = NULL WHERE id = ?"
      ).run(bean.id);
      db.prepare(
        "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, 'freeze', ?)"
      ).run(bean.id, today);
    }
  });

  freezeTx();
}
