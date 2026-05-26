#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/kev_monitor"
SERVICE_NAME="kev_monitor"

BINARY_URL="https://github.com/quantumcore/kev_monitor/releases/download/V.1/kev_monitor-linux-x86_64"
BINARY_NAME="kev_monitor"

# ── Root check ─────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

# ── Install deps check ─────────────────────────────────────
command -v curl >/dev/null || command -v wget >/dev/null || {
  echo "curl or wget required"
  exit 1
}

# ── Create install directory ───────────────────────────────
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/reports"

# ── Download binary ────────────────────────────────────────
TMPFILE=$(mktemp)

echo "[*] Downloading kev_monitor..."
if command -v curl >/dev/null; then
  curl -fsSL "$BINARY_URL" -o "$TMPFILE"
else
  wget -qO "$TMPFILE" "$BINARY_URL"
fi

chmod +x "$TMPFILE"
mv "$TMPFILE" "$INSTALL_DIR/$BINARY_NAME"

# ── System user ────────────────────────────────────────────
if ! id "$SERVICE_NAME" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_NAME"
fi

# ── Permissions ─────────────────────────────────────────────
chown -R "$SERVICE_NAME:$SERVICE_NAME" "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR/$BINARY_NAME"

# ── systemd service ─────────────────────────────────────────
cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=KEV Monitor Service
After=network-online.target

[Service]
Type=simple
User=$SERVICE_NAME
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BINARY_NAME
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ── Enable + start ──────────────────────────────────────────
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo "[✓] Installed successfully"
echo "[✓] Service: systemctl status $SERVICE_NAME"
echo "[✓] Logs: journalctl -u $SERVICE_NAME -f"
