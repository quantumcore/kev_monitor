mod config;
mod db;
mod kev;
mod notify;
mod report;

use std::thread;
use std::time::Duration;

use crate::config::AppConfig;
use crate::db::Database;
use crate::kev::KevClient;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("[KEV Monitor] Starting...");

    let cfg = AppConfig::load("settings.ini")?;
    println!(
        "[KEV Monitor] Check interval: {} day(s), DB: {}",
        cfg.check_days, cfg.db_path
    );

    let db = Database::open(&cfg.db_path)?;
    db.init()?;

    let client = KevClient::new(&cfg.kev_url);

    loop {
        println!("[KEV Monitor] Running check cycle...");

        match run_cycle(&cfg, &db, &client) {
            Ok(updated) => {
                if updated {
                    println!("[KEV Monitor] Catalog updated — report written & notification sent.");
                } else {
                    println!("[KEV Monitor] No changes detected.");
                }
            }
            Err(e) => {
                eprintln!("[KEV Monitor] Cycle error: {e}");
            }
        }

        let sleep_secs = (cfg.check_days as u64) * 86_400;
        println!(
            "[KEV Monitor] Next check in {} second(s) ({} day(s)).",
            sleep_secs, cfg.check_days
        );
        thread::sleep(Duration::from_secs(sleep_secs));
    }
}

fn run_cycle(
    cfg: &AppConfig,
    db: &Database,
    client: &KevClient,
) -> Result<bool, Box<dyn std::error::Error>> {
    let (bytes, sha1) = client.fetch_bytes()?;
    println!("[KEV Monitor] Fetched {} bytes, SHA-1: {}", bytes.len(), sha1);

    let last = db.latest_record()?;
    if let Some(ref rec) = last {
        if rec.kev_hash == sha1 {
            return Ok(false);
        }
        println!(
            "[KEV Monitor] Hash changed: {} -> {}",
            &rec.kev_hash[..8],
            &sha1[..8]
        );
    } else {
        println!("[KEV Monitor] First run — storing baseline.");
    }

    let catalog = kev::parse_catalog(&bytes)?;
    let last_cve = catalog
        .vulnerabilities
        .first()
        .map(|v| v.cve_id.clone())
        .unwrap_or_default();
    let prev_last_cve = last.as_ref().map(|r| r.last_cve_id.as_str()).unwrap_or("");

    let new_entries: Vec<&kev::KevEntry> = if prev_last_cve.is_empty() {
        catalog.vulnerabilities.iter().collect()
    } else {
        let mut seen = false;
        catalog
            .vulnerabilities
            .iter()
            .filter(|v| {
                if v.cve_id == prev_last_cve {
                    seen = true;
                    return false;
                }
                !seen
            })
            .collect()
    };

    println!("[KEV Monitor] {} new/changed entries.", new_entries.len());

    let report_path = report::write_report(&new_entries, &catalog, cfg)?;
    println!("[KEV Monitor] Report written to {}", report_path.display());

    db.insert_record(&sha1, &last_cve)?;

    notify::send(
        "KEV Catalog Updated",
        &format!(
            "{} new entries added. Report: {}",
            new_entries.len(),
            report_path.display()
        ),
    );

    Ok(true)
}
