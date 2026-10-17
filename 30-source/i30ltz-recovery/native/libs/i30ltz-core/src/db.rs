//! SQLite database — case storage, drive history, AI conversation log.

use crate::Result;
use rusqlite::Connection;
use std::path::Path;

pub struct I30Db {
    conn: Connection,
}

impl I30Db {
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        conn.busy_timeout(std::time::Duration::from_secs(5))?;
        conn.pragma_update(None, "foreign_keys", true)?;
        let db = Self { conn };
        db.migrate()?;
        Ok(db)
    }

    fn migrate(&self) -> Result<()> {
        self.conn.execute_batch(
            "
            PRAGMA journal_mode=WAL;

            CREATE TABLE IF NOT EXISTS cases (
                id          TEXT    PRIMARY KEY,
                created_at  TEXT    NOT NULL,
                updated_at  TEXT    NOT NULL,
                client      TEXT    NOT NULL,
                device      TEXT    NOT NULL,
                status      TEXT    NOT NULL DEFAULT 'Open',
                priority    TEXT    NOT NULL DEFAULT 'Normal',
                data_json   TEXT    NOT NULL
            );

            CREATE TABLE IF NOT EXISTS drives (
                id          TEXT    PRIMARY KEY,
                case_id     TEXT    REFERENCES cases(id),
                device      TEXT    NOT NULL,
                model       TEXT,
                serial      TEXT,
                scanned_at  TEXT    NOT NULL,
                data_json   TEXT    NOT NULL
            );

            CREATE TABLE IF NOT EXISTS ai_log (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                case_id     TEXT    REFERENCES cases(id),
                ts          TEXT    NOT NULL,
                role        TEXT    NOT NULL,  -- 'user' | 'assistant'
                content     TEXT    NOT NULL
            );
        ",
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn migration_is_repeatable_and_creates_tables() {
        let db = I30Db::open(":memory:").unwrap();
        db.migrate().unwrap();
        for table in ["cases", "drives", "ai_log"] {
            let exists: i64 = db
                .conn
                .query_row(
                    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?1",
                    [table],
                    |row| row.get(0),
                )
                .unwrap();
            assert_eq!(exists, 1);
        }
    }
    #[test]
    fn orphan_drive_is_rejected() {
        let db = I30Db::open(":memory:").unwrap();
        let result = db.conn.execute(
            "INSERT INTO drives (id,case_id,device,scanned_at,data_json) VALUES ('drive','missing','fixture','now','{}')", []);
        assert!(matches!(result, Err(rusqlite::Error::SqliteFailure(_, _))));
    }
}
