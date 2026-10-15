#!/usr/bin/env bash
# =====================================================================
# Google Photos Unlimited Auto-Sync - Enable Linux Auto-Start (systemd)
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="google-unlimited.service"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}Enabling Google Photos Auto-Sync on startup (Linux systemd)...${NC}"

if ! command -v systemctl >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] systemctl not found. Your Linux distribution does not appear to use systemd.${NC}"
    echo "You can manually add './watch_and_upload.sh' to your desktop autostart or cron (@reboot)."
    exit 1
fi

mkdir -p "$USER_SYSTEMD_DIR"

# Generate systemd unit with exact local directory
cat << EOF > "$USER_SYSTEMD_DIR/$SERVICE_NAME"
[Unit]
Description=Google Photos Unlimited Auto-Sync Watcher
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/watch_and_upload.sh
Restart=on-failure
RestartSec=10
KillMode=mixed

[Install]
WantedBy=default.target
EOF

echo -e "${GREEN}[OK] Service unit created at: $USER_SYSTEMD_DIR/$SERVICE_NAME${NC}"

# Reload and enable
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
systemctl --user restart "$SERVICE_NAME"

# Enable lingering if loginctl is available so the service runs in background without terminal
if command -v loginctl >/dev/null 2>&1; then
    CURRENT_USER="${USER:-$(id -un 2>/dev/null || whoami 2>/dev/null || echo "")}"
    if [ -n "$CURRENT_USER" ]; then
        loginctl enable-linger "$CURRENT_USER" 2>/dev/null || true
    fi
fi

echo ""
echo -e "${GREEN}==========================================================${NC}"
echo -e "${GREEN}  *  Auto-Sync has been enabled for Linux startup!${NC}"
echo -e "${GREEN}==========================================================${NC}"
echo "Status check:  systemctl --user status $SERVICE_NAME"
echo "View logs:     ./view_logs.sh  or  journalctl --user -u $SERVICE_NAME -f"
echo "Disable anytime: ./disable_startup.sh"
echo ""
