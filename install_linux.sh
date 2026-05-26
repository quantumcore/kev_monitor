#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="/opt/kev_monitor"
SERVICE_NAME="kev_monitor"
GITHUB_REPO="quantumcore/kev_monitor"

# ── Helpers ───────────────────────────────────────────────────────────────────

step() { echo -e "\e[36m[*] $*\e[0m"; }
ok()   { echo -e "\e[32m[✓] $*\e[0m"; }
fail() { echo -e "\e[31m[✗] $*\e[0m" >&2; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────

[[ $EUID -eq 0 ]] || fail "Please run as root (sudo $0)"

# ── Uninstall ─────────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--uninstall" ]]; then
    step "Stopping and disabling service..."
    systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    step "Removing service unit..."
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload

    read -rp "Remove install directory '$INSTALL_DIR'? [y/N] " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
        ok "Install directory removed."
    fi

    # Remove system user if it exists
    if id "$SERVICE_NAME" &>/dev/null; then
        userdel "$SERVICE_NAME"
        ok "System user '$SERVICE_NAME' removed."
    fi

    ok "kev_monitor uninstalled."
    exit 0
fi

# ── Detect architecture ───────────────────────────────────────────────────────

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ASSET_PATTERN="kev_monitor-linux-x86_64"  ;;
    aarch64) ASSET_PATTERN="kev_monitor-linux-aarch64" ;;
    armv7l)  ASSET_PATTERN="kev_monitor-linux-armv7"   ;;
    *) fail "Unsupported architecture: $ARCH" ;;
esac

# ── Resolve latest GitHub release ─────────────────────────────────────────────

step "Querying GitHub for the latest release..."

API_URL="https://api.github.com/repos/$GITHUB_REPO/releases/latest"

if command -v curl &>/dev/null; then
    RELEASE_JSON=$(curl -fsSL -H "User-Agent: kev_monitor-installer" "$API_URL")
elif command -v wget &>/dev/null; then
    RELEASE_JSON=$(wget -qO- --header="User-Agent: kev_monitor-installer" "$API_URL")
else
    fail "Neither curl nor wget found. Install one and retry."
fi

VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
[[ -n "$VERSION" ]] || fail "Could not parse release tag from GitHub API response."
ok "Latest release: $VERSION"

# Extract download URL for the binary asset
# grep -o + || true prevents set -e from firing on no match
BINARY_URL=$(echo "$RELEASE_JSON" \
    | grep -o '"browser_download_url":"[^"]*'"$ASSET_PATTERN"'[^"]*"' \
    | grep -o 'https://[^"]*' \
    | head -1 || true)
[[ -n "$BINARY_URL" ]] || fail "No asset matching '$ASSET_PATTERN' found in release $VERSION. Ensure the binary is attached to the release."

# Optional settings.ini asset
CONFIG_URL=$(echo "$RELEASE_JSON" \
    | grep -o '"browser_download_url":"[^"]*settings\.ini[^"]*"' \
    | grep -o 'https://[^"]*' \
    | head -1 || true)

# ── Download ──────────────────────────────────────────────────────────────────

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

BINARY_TMP="$TMPDIR/kev_monitor"

step "Downloading binary ($ARCH)..."
if command -v curl &>/dev/null; then
    curl -fsSL -o "$BINARY_TMP" "$BINARY_URL"
else
    wget -qO "$BINARY_TMP" "$BINARY_URL"
fi
chmod +x "$BINARY_TMP"
ok "Binary downloaded."

# ── Install directory ─────────────────────────────────────────────────────────

step "Creating install directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/reports"

# ── Config — download, keep existing, or write built-in default ───────────────

CONFIG_DEST="$INSTALL_DIR/settings.ini"
if [[ -f "$CONFIG_DEST" ]]; then
    step "Existing settings.ini retained (not overwritten)."
elif [[ -n "$CONFIG_URL" ]]; then
    step "Downloading default settings.ini..."
    if command -v curl &>/dev/null; then
        curl -fsSL -o "$CONFIG_DEST" "$CONFIG_URL"
    else
        wget -qO "$CONFIG_DEST" "$CONFIG_URL"
    fi
    ok "settings.ini downloaded."
else
    step "No settings.ini in release — writing built-in default..."
    cat > "$CONFIG_DEST" << 'INI'
[CONFIG]
; Days between KEV catalog checks
CHECK = 1

; SQLite database path (relative to install dir)
DB_PATH = kev_monitor.db

; Directory where Markdown reports are written
REPORT_DIR = reports

; CISA KEV feed URL
KEV_URL = https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json
INI
    ok "Default settings.ini written."
fi

# ── Deploy binary ─────────────────────────────────────────────────────────────

step "Installing binary..."
cp "$BINARY_TMP" "$INSTALL_DIR/kev_monitor"

# ── System user ───────────────────────────────────────────────────────────────

step "Ensuring system user '$SERVICE_NAME' exists..."
if ! id "$SERVICE_NAME" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_NAME"
    ok "System user created."
else
    step "System user '$SERVICE_NAME' already exists."
fi

# ── Permissions ───────────────────────────────────────────────────────────────

chown -R "$SERVICE_NAME:$SERVICE_NAME" "$INSTALL_DIR"
chmod 750 "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR/kev_monitor"

# ── Systemd unit ──────────────────────────────────────────────────────────────

step "Writing systemd service unit..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" << UNIT
[Unit]
Description=CISA KEV Catalog Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_NAME
Group=$SERVICE_NAME
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/kev_monitor
Restart=on-failure
RestartSec=30s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# Harden the service
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
UNIT

# ── Enable & start ────────────────────────────────────────────────────────────

step "Enabling and starting service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# Brief pause then verify
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    ok "Service is running."
else
    fail "Service failed to start. Run: journalctl -u $SERVICE_NAME -n 50"
fi

echo ""
ok "kev_monitor $VERSION installed and running."
echo "    Config:   $CONFIG_DEST"
echo "    Reports:  $INSTALL_DIR/reports/"
echo "    Logs:     journalctl -u $SERVICE_NAME -f"
echo "    Status:   systemctl status $SERVICE_NAME"
echo ""
echo "    To uninstall: sudo $0 --uninstall"
