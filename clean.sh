#!/usr/bin/env bash
set -euo pipefail

echo "=== Cleaning artifacts ==="

# Rust build output
if [ -d target ]; then
    rm -rf target
    echo "  [removed] target/  (Rust build artifacts)"
fi

# SQLite DB (contains local CVE check history, host metadata)
if [ -f kev_monitor.db ]; then
    rm -f kev_monitor.db
    echo "  [removed] kev_monitor.db  (local CVE tracking database)"
fi

# Generated report files
if [ -d reports ]; then
    rm -rf reports
    echo "  [removed] reports/  (generated CVE report files)"
fi

# Prebuilt binaries (platform-specific, not in target/)
rm -f kev_monitor_linux_*
rm -f kev_monitor_macos_*
rm -f kev_monitor_windows_*
echo "  [cleaned] prebuilt binaries (kev_monitor_*)"

# Cargo.lock — optional; remove if you want maximum freshness
# rm -f Cargo.lock

echo "=== Done. Project is now clean for public release. ==="
echo "Remember to also check for:"
echo "  - .env / .env.local files"
echo "  - IDE settings (.vscode/, .idea/)"
echo "  - Any hardcoded API keys or tokens in source code"
