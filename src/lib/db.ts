import Database from "better-sqlite3";
import path from "path";
import { initializeSchema } from "./schema";

let db: Database.Database | null = null;

export function getDb(dbPath?: string): Database.Database {
  if (db) return db;

  const resolvedPath = dbPath || path.join(process.cwd(), "coffee.db");
  db = new Database(resolvedPath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  initializeSchema(db);
  return db;
}

/**
 * Create an in-memory database for testing.
 */
export function createTestDb(): Database.Database {
  const testDb = new Database(":memory:");
  testDb.pragma("foreign_keys = ON");
  initializeSchema(testDb);
  return testDb;
}

/**
 * Close the singleton database connection.
 */
export function closeDb(): void {
  if (db) {
    db.close();
    db = null;
  }
}
