#!/usr/bin/env bash
# =====================================================================
# Google Photos Unlimited Auto-Sync - Linux Activity Log Viewer
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="$SCRIPT_DIR/gphotos.db"

# Color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

if [ ! -f "$DB" ]; then
    echo -e "${YELLOW}[INFO] Database '$DB' does not exist yet.${NC}"
    echo "Run ./watch_and_upload.sh first to generate activity logs."
    exit 0
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] sqlite3 is not installed. Please run: sudo apt install sqlite3${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}==========================================================${NC}"
echo -e "${GREEN}  *  Google Photos Sync - Activity Logs (Last 30)${NC}"
echo -e "${GRAY}  Database: $DB${NC}"
echo -e "${CYAN}==========================================================${NC}"

# Get last 30 logs ordered chronologically
LOG_ROWS=$(sqlite3 "$DB" "SELECT timestamp, level, message FROM (SELECT id, timestamp, level, message FROM logs ORDER BY id DESC LIMIT 30) ORDER BY id ASC;" 2>/dev/null || true)

if [ -n "$LOG_ROWS" ]; then
    while IFS='|' read -r timestamp level message; do
        COLOR="$GRAY"
        case "$level" in
            "OK")    COLOR="$GREEN" ;;
            "WARN")  COLOR="$YELLOW" ;;
            "ERROR") COLOR="$RED" ;;
        esac
        echo -e "[$timestamp][${COLOR}$level${NC}] $message"
    done <<< "$LOG_ROWS"
else
    echo -e "  ${GRAY}No activity logs found.${NC}"
fi

echo -e "${CYAN}==========================================================${NC}"
echo ""
