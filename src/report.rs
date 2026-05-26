use std::fs;
use std::path::PathBuf;

use chrono::Local;

use crate::config::AppConfig;
use crate::kev::{KevCatalog, KevEntry};

/// Write a Markdown report for `entries` and return the file path.
pub fn write_report(
    entries: &[&KevEntry],
    catalog: &KevCatalog,
    cfg: &AppConfig,
) -> Result<PathBuf, Box<dyn std::error::Error>> {
    fs::create_dir_all(&cfg.report_dir)?;

    let timestamp = Local::now().format("%Y%m%d_%H%M%S");
    let filename = format!("kev_report_{}.md", timestamp);
    let path = PathBuf::from(&cfg.report_dir).join(&filename);

    let mut md = String::new();

    // Header
    md.push_str(&format!("# CISA KEV Catalog Update Report\n\n"));
    md.push_str(&format!(
        "**Generated:** {}  \n",
        Local::now().format("%Y-%m-%d %H:%M:%S")
    ));
    md.push_str(&format!("**Catalog title:** {}  \n", catalog.title));
    md.push_str(&format!("**Catalog version:** {}  \n", catalog.catalog_version));
    md.push_str(&format!("**Catalog date released:** {}  \n", catalog.date_released));
    md.push_str(&format!("**Total vulnerabilities in catalog:** {}  \n", catalog.count));
    md.push_str(&format!("**New entries in this report:** {}  \n\n", entries.len()));
    md.push_str("---\n\n");

    if entries.is_empty() {
        md.push_str("_No new entries since the last check._\n");
    } else {
        md.push_str("## New / Updated Entries\n\n");

        for (i, e) in entries.iter().enumerate() {
            md.push_str(&format!("### {}. {}\n\n", i + 1, e.cve_id));

            md.push_str(&format!(
                "| Field | Value |\n|---|---|\n"
            ));
            md.push_str(&row("CVE ID", &e.cve_id));
            md.push_str(&row("Vendor / Project", &e.vendor_project));
            md.push_str(&row("Product", &e.product));
            md.push_str(&row("Vulnerability Name", &e.vulnerability_name));
            md.push_str(&row("Date Added", &e.date_added));
            md.push_str(&row("Due Date", &e.due_date));
            md.push_str(&row("Ransomware Use", &e.known_ransomware_campaign_use));

            md.push_str("\n**Description:**  \n");
            md.push_str(&e.short_description);
            md.push_str("\n\n**Required Action:**  \n");
            md.push_str(&e.required_action);

            if !e.notes.is_empty() {
                md.push_str("\n\n**Notes:**  \n");
                md.push_str(&e.notes);
            }

            md.push_str("\n\n---\n\n");
        }
    }

    fs::write(&path, &md)?;
    Ok(path)
}

fn row(label: &str, value: &str) -> String {
    let safe = value.replace('|', "\\|");
    format!("| {} | {} |\n", label, safe)
}
