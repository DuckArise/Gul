#!/usr/bin/env bash
# =====================================================================
# Google Photos Unlimited Auto-Sync - Linux Status Viewer
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
    echo "Run ./watch_and_upload.sh first to start tracking uploads."
    exit 0
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] sqlite3 is not installed. Please run: sudo apt install sqlite3${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}==========================================================${NC}"
echo -e "${GREEN}  *  Google Photos Sync Status${NC}"
echo -e "${GRAY}  Database: $DB${NC}"
echo -e "${CYAN}==========================================================${NC}"

TOTAL_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM uploads;" 2>/dev/null || echo 0)
RETRY_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM retry_queue;" 2>/dev/null || echo 0)

echo -e "  Total Uploaded Files : ${YELLOW}$TOTAL_COUNT${NC}"
if [ "$RETRY_COUNT" -gt 0 ]; then
    echo -e "  Pending Retries      : ${RED}$RETRY_COUNT${NC}"
else
    echo -e "  Pending Retries      : ${GREEN}0${NC}"
fi

# Last 10 uploads
echo ""
echo -e "${CYAN}  Last 10 Uploads:${NC}"
LAST_UPLOADS=$(sqlite3 "$DB" "SELECT uploaded_at, path FROM uploads ORDER BY uploaded_at DESC LIMIT 10;" 2>/dev/null || true)
if [ -n "$LAST_UPLOADS" ]; then
    while IFS='|' read -r uploaded_at fpath; do
        fname=$(basename "$fpath")
        echo -e "    ${GRAY}[$uploaded_at]${NC} $fname"
    done <<< "$LAST_UPLOADS"
else
    echo -e "    ${GRAY}(None yet)${NC}"
fi

# Pending retries
if [ "$RETRY_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}  Pending Retries in Queue:${NC}"
    RETRIES=$(sqlite3 "$DB" "SELECT path, attempts FROM retry_queue;" 2>/dev/null || true)
    while IFS='|' read -r fpath attempts; do
        fname=$(basename "$fpath")
        echo -e "    ${YELLOW}$fname (attempt $attempts)${NC}"
    done <<< "$RETRIES"
fi

echo -e "${CYAN}==========================================================${NC}"
echo ""
