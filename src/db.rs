use rusqlite::{Connection, params};

pub struct DbRecord {
    pub timestamp: i64,
    pub kev_hash: String,
    pub last_cve_id: String,
}

pub struct Database {
    conn: Connection,
}

impl Database {
    pub fn open(path: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let conn = Connection::open(path)?;
        Ok(Self { conn })
    }

    /// Create table if it doesn't exist.
    pub fn init(&self) -> Result<(), Box<dyn std::error::Error>> {
        self.conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS kev_checks (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp   INTEGER NOT NULL,
                kev_hash    TEXT    NOT NULL,
                last_cve_id TEXT    NOT NULL
            );",
        )?;
        Ok(())
    }

    /// Return the most recently inserted record, if any.
    pub fn latest_record(&self) -> Result<Option<DbRecord>, Box<dyn std::error::Error>> {
        let mut stmt = self.conn.prepare(
            "SELECT timestamp, kev_hash, last_cve_id
             FROM kev_checks
             ORDER BY id DESC
             LIMIT 1",
        )?;

        let mut rows = stmt.query([])?;
        if let Some(row) = rows.next()? {
            Ok(Some(DbRecord {
                timestamp:   row.get(0)?,
                kev_hash:    row.get(1)?,
                last_cve_id: row.get(2)?,
            }))
        } else {
            Ok(None)
        }
    }

    /// Insert a new check record with the current Unix timestamp.
    pub fn insert_record(
        &self,
        hash: &str,
        last_cve_id: &str,
    ) -> Result<(), Box<dyn std::error::Error>> {
        use std::time::{SystemTime, UNIX_EPOCH};
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        self.conn.execute(
            "INSERT INTO kev_checks (timestamp, kev_hash, last_cve_id) VALUES (?1, ?2, ?3)",
            params![ts, hash, last_cve_id],
        )?;
        Ok(())
    }
}
