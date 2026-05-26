# KEV Monitor

A lightweight background service written in Rust that watches the [CISA Known Exploited Vulnerabilities (KEV) catalog](https://www.cisa.gov/known-exploited-vulnerabilities-catalog) for changes, writes a Markdown report of new entries, and sends a desktop toast notification.

Built as an extension of [Zeus Threat Intelligence](https://code-9.io/zeus.php) pipeline for Automated KEV testing against a software inventory, refactored into a standalone portable utility.

![img](https://github.com/quantumcore/kev_monitor/blob/main/kev.png?raw=true)
![img2](https://github.com/quantumcore/kev_monitor/blob/main/report.png?raw=true)
### Install

Windows (Run in Powershell):
``iwr https://github.com/quantumcore/kev_monitor/raw/refs/heads/main/install_windows.ps1 | iex``

Linux 
``curl -fsSL https://raw.githubusercontent.com/quantumcore/kev_monitor/refs/heads/main/install_linux.sh | sudo bash``

---

## Features

| Feature | Detail |
|---|---|
| Periodic polling | Configurable interval (default: every 1 day) |
| SHA-1 change detection | Only acts when the catalog actually changes |
| SQLite audit log | Stores every check: timestamp, hash, last CVE ID |
| Markdown report | One file per detected change in `reports/` |
| Toast notifications | Native: PowerShell on Windows, `notify-send` on Linux |
| Cross-platform | Available for Windows & Linux (x86-64) |

---

## Configuration (`settings.ini`)

```ini
[CONFIG]
CHECK      = 1          ; days between checks (integer)
DB_PATH    = kev_monitor.db
REPORT_DIR = reports
KEV_URL    = https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json
```
---

## Toast Notifications

| Platform | Mechanism |
|---|---|
| Windows 10/11 | PowerShell + `Windows.UI.Notifications` WinRT API |
| Linux | `notify-send` (install `libnotify-bin` if missing) |

> **Note on Linux services:** `notify-send` requires a running D-Bus session (i.e. a logged-in desktop user). When running as a headless `systemd` service the notification will silently fail; the report and DB entry are still written correctly.

---

## Reports

Each detected change produces `reports/kev_report_<YYYYMMDD_HHMMSS>.md` containing:

- Catalog metadata (version, date released, total count)
- A table per new CVE entry (ID, vendor, product, description, required action, due date, ransomware use)
