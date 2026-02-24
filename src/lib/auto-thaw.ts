import Database from "better-sqlite3";

/**
 * Auto-thaw beans whose planned_thaw_date has arrived.
 * Sets is_frozen = 0, clears planned_thaw_date, and inserts a thaw event.
 */
export function autoThawBeans(db: Database.Database, today: string): void {
  const beansToThaw = db
    .prepare(
      "SELECT id FROM beans WHERE is_frozen = 1 AND planned_thaw_date IS NOT NULL AND planned_thaw_date <= ?"
    )
    .all(today) as { id: string }[];

  if (beansToThaw.length === 0) return;

  const thawTx = db.transaction(() => {
    for (const bean of beansToThaw) {
      db.prepare(
        "UPDATE beans SET is_frozen = 0, planned_thaw_date = NULL WHERE id = ?"
      ).run(bean.id);
      db.prepare(
        "INSERT INTO freeze_events (bean_id, event_type, event_date) VALUES (?, 'thaw', ?)"
      ).run(bean.id, today);
    }
  });

  thawTx();
}
