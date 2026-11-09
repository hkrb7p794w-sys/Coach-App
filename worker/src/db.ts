/**
 * SQL-Datenbank für Konten, Freunde und Feed: Cloudflare D1 „coach-social“ (Binding `DB`, SQLite).
 *
 * Das Schema legt der Worker selbst an (`CREATE TABLE IF NOT EXISTS`, einmal je Isolate), damit der Deploy keine
 * Migrationen und keine zusätzlichen Token-Rechte braucht. Neue Spalten kommen nur als neue Tabellen oder mit
 * `ALTER TABLE` in `MIGRATIONS` dazu – nie bestehende Tabellen umbauen.
 *
 * Gratis-Plan (Cloudflare-Doku D1 Pricing, Stand 10/2026): 5 Mio. gelesene und 100.000 geschriebene Zeilen am Tag,
 * 5 GB Speicher. Darüber schlagen Abfragen bis 00:00 UTC fehl; gespeicherte Daten bleiben erhalten.
 */

/** Das Nötigste aus `D1Database`; in Tests ersetzt durch SQLite aus Node (`test/sqlite.ts`). */
export interface SqlStatement {
  bind(...values: unknown[]): SqlStatement;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  all<T = Record<string, unknown>>(): Promise<{ results: T[] }>;
  run(): Promise<{ meta?: { changes?: number } }>;
}

export interface SqlDatabase {
  prepare(sql: string): SqlStatement;
  batch(statements: SqlStatement[]): Promise<unknown[]>;
}

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    pw_hash TEXT NOT NULL,
    recovery_hash TEXT NOT NULL,
    is_admin INTEGER NOT NULL DEFAULT 0,
    invited_by TEXT,
    guest_id TEXT UNIQUE,
    created_at INTEGER NOT NULL,
    failed_logins INTEGER NOT NULL DEFAULT 0,
    locked_until INTEGER NOT NULL DEFAULT 0
  )`,
  `CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    device TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_used INTEGER NOT NULL
  )`,
  "CREATE INDEX IF NOT EXISTS sessions_account ON sessions(account_id)",
  `CREATE TABLE IF NOT EXISTS invites (
    code TEXT PRIMARY KEY,
    created_by TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    used_by TEXT
  )`,
  "CREATE INDEX IF NOT EXISTS invites_creator ON invites(created_by)",
];

const ready = new WeakMap<SqlDatabase, Promise<void>>();

/** Legt fehlende Tabellen an; nur der erste Aufruf je Datenbank und Isolate kostet etwas. */
export function ensureSchema(db: SqlDatabase): Promise<void> {
  let promise = ready.get(db);
  if (!promise) {
    promise = db.batch(SCHEMA.map((sql) => db.prepare(sql))).then(() => undefined);
    // Bei einem Fehler beim nächsten Aufruf neu versuchen.
    promise.catch(() => ready.delete(db));
    ready.set(db, promise);
  }
  return promise;
}
