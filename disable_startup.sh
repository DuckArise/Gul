#!/usr/bin/env bash
# =====================================================================
# Google Photos Unlimited Auto-Sync - Disable Linux Auto-Start (systemd)
# =====================================================================
set -euo pipefail

SERVICE_NAME="google-unlimited.service"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}Disabling Google Photos Auto-Sync startup service...${NC}"

if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
fi

if [ -f "$USER_SYSTEMD_DIR/$SERVICE_NAME" ]; then
    rm -f "$USER_SYSTEMD_DIR/$SERVICE_NAME"
    echo -e "${GREEN}[OK] Removed service unit: $USER_SYSTEMD_DIR/$SERVICE_NAME${NC}"
fi

echo ""
echo -e "${GREEN}==========================================================${NC}"
echo -e "${GREEN}  *  Google Photos Auto-Sync startup has been disabled.${NC}"
echo -e "${GREEN}==========================================================${NC}"
echo ""
