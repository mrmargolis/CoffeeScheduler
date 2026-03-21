import Database from "better-sqlite3";

/** Renumber all beans that have a display_order so values are sequential (1, 2, 3, ...) with no gaps. */
export function resequenceDisplayOrder(db: Database.Database): void {
  const beans = db
    .prepare("SELECT id FROM beans WHERE display_order IS NOT NULL ORDER BY display_order")
    .all() as { id: string }[];
  const update = db.prepare("UPDATE beans SET display_order = ? WHERE id = ?");
  for (let i = 0; i < beans.length; i++) {
    update.run(i + 1, beans[i].id);
  }
}
