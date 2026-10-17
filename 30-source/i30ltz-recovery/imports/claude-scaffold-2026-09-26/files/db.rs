//! SQLite database — case storage, drive history, AI conversation log.

use rusqlite::{Connection, params};
use std::path::Path;
use crate::Result;

pub struct I30Db {
    conn: Connection,
}

impl I30Db {
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;
        let db = Self { conn };
        db.migrate()?;
        Ok(db)
    }

    fn migrate(&self) -> Result<()> {
        self.conn.execute_batch("
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
        ")?;
        Ok(())
    }
}
