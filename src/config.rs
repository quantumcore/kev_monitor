use configparser::ini::Ini;

const DEFAULT_KEV_URL: &str =
    "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json";

pub struct AppConfig {
    /// How many days between checks
    pub check_days: i64,
    /// SQLite database path
    pub db_path: String,
    /// Directory for Markdown reports
    pub report_dir: String,
    /// KEV feed URL (overridable)
    pub kev_url: String,
}

impl AppConfig {
    pub fn load(path: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let mut ini = Ini::new();

        // settings.ini is optional — fall back to defaults if missing
        let _ = ini.load(path);

        let check_days = ini
            .getint("CONFIG", "CHECK")
            .unwrap_or(None)
            .unwrap_or(7);

        let db_path = ini
            .get("CONFIG", "DB_PATH")
            .unwrap_or_else(|| "kev_monitor.db".to_string());

        let report_dir = ini
            .get("CONFIG", "REPORT_DIR")
            .unwrap_or_else(|| "reports".to_string());

        let kev_url = ini
            .get("CONFIG", "KEV_URL")
            .unwrap_or_else(|| DEFAULT_KEV_URL.to_string());

        Ok(Self {
            check_days,
            db_path,
            report_dir,
            kev_url,
        })
    }
}
