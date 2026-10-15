#!/usr/bin/env bash
# =====================================================================
# Google Photos Unlimited Auto-Sync - Stop Linux Background Watcher
# =====================================================================
set -euo pipefail

# Color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}Stopping Google Photos background watcher...${NC}"

STOPPED=0

# Find watch_and_upload.sh PIDs
PIDS=$(pgrep -f "watch_and_upload.sh" || true)

if [ -n "$PIDS" ]; then
    for pid in $PIDS; do
        if [ "$pid" != "$$" ]; then
            kill "$pid" 2>/dev/null || true
            echo -e "${GREEN}[OK] Sent terminate signal to watcher PID $pid${NC}"
            STOPPED=1
        fi
    done
fi

# Stop any orphan inotifywait processes spawned by the watcher
INOTIFY_PIDS=$(pgrep -f "inotifywait -m -r -e close_write,moved_to" || true)
if [ -n "$INOTIFY_PIDS" ]; then
    for ipid in $INOTIFY_PIDS; do
        kill "$ipid" 2>/dev/null || true
        echo -e "${GREEN}[OK] Stopped inotifywait listener PID $ipid${NC}"
        STOPPED=1
    done
fi

# Also check systemd user service if running
if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user is-active --quiet google-unlimited 2>/dev/null; then
        systemctl --user stop google-unlimited
        echo -e "${GREEN}[OK] Stopped systemd user service 'google-unlimited'${NC}"
        STOPPED=1
    fi
fi

if [ "$STOPPED" -eq 1 ]; then
    echo -e "${GREEN}All background watcher instances have been stopped.${NC}"
else
    echo -e "${YELLOW}No active watcher instances were found running.${NC}"
fi
