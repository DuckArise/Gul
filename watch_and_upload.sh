#!/usr/bin/env bash
# =====================================================================
# Google Photos Unlimited Auto-Sync - Linux Background Watcher
# =====================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="$SCRIPT_DIR/gphotos.db"

# 1. Discover gotohp-cli binary
GOTOHP=""
for cand in "$SCRIPT_DIR/gotohp-cli" "$SCRIPT_DIR/gotohp-cli_amd64" "$SCRIPT_DIR/gotohp-cli_arm64"; do
    if [ -x "$cand" ] || [ -f "$cand" ]; then
        chmod +x "$cand" 2>/dev/null || true
        GOTOHP="$cand"
        break
    fi
done

if [ -z "$GOTOHP" ]; then
    if command -v gotohp-cli >/dev/null 2>&1; then
        GOTOHP="$(command -v gotohp-cli)"
    else
        echo "ERROR: gotohp-cli binary not found in $SCRIPT_DIR or system PATH."
        echo "Please run: ./setup_linux.sh"
        exit 1
    fi
fi

# Portable config check (uses gotohp.config if placed in script folder)
if [ -f "$SCRIPT_DIR/gotohp.config" ]; then
    GOTOHP_CMD=("$GOTOHP" "--config" "$SCRIPT_DIR/gotohp.config")
else
    GOTOHP_CMD=("$GOTOHP")
fi

# Verify active account
CREDS_OUTPUT="$("${GOTOHP_CMD[@]}" creds list 2>&1 || true)"
if ! echo "$CREDS_OUTPUT" | grep -q "\*"; then
    echo ""
    echo "=========================================================="
    echo "  ACTION REQUIRED: No Google Account Logged In!"
    echo "=========================================================="
    echo "  Please sign in by running:"
    echo "    $GOTOHP creds add \"<oauth_token>\""
    echo "=========================================================="
    exit 1
fi

# 2. Database Initialization (Identical schema to Windows gphotos.db)
sqlite3 "$DB" << 'EOF'
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;

CREATE TABLE IF NOT EXISTS uploads (
    path        TEXT PRIMARY KEY,
    media_key   TEXT,
    uploaded_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS retry_queue (
    path         TEXT PRIMARY KEY,
    attempts     INTEGER NOT NULL DEFAULT 0,
    last_attempt TEXT
);

CREATE TABLE IF NOT EXISTS logs (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    level     TEXT NOT NULL,
    message   TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_logs_ts    ON logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_level ON logs(level);
EOF

# Logging helper
write_log() {
    local msg="$1"
    local level="${2:-INFO}"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    sqlite3 "$DB" "INSERT INTO logs(level, message) VALUES ('$level', '$(echo "$msg" | sed "s/'/''/g")');" 2>/dev/null || true
    echo "[$ts][$level] $msg"
}

# 3. Discover Watched Folders (XDG user directories)
WATCH_DIRS=()
for folder in "$HOME/Downloads" "$HOME/Pictures" "$HOME/Desktop" "$HOME/Documents" "$HOME/Music" "$HOME/Videos"; do
    if [ -d "$folder" ]; then
        WATCH_DIRS+=("$folder")
    fi
done

if [ ${#WATCH_DIRS[@]} -eq 0 ]; then
    mkdir -p "$HOME/Pictures"
    WATCH_DIRS=("$HOME/Pictures")
fi

VALID_EXT="^(jpg|jpeg|png|heic|webp|gif|mp4|mov|mkv|avi|dng)$"
MIN_BYTES=10240

is_uploaded() {
    local fpath="$1"
    local count
    count="$(sqlite3 "$DB" "SELECT COUNT(*) FROM uploads WHERE path = '$(echo "$fpath" | sed "s/'/''/g")';" 2>/dev/null || echo 0)"
    [ "$count" -gt 0 ]
}

save_upload() {
    local fpath="$1"
    local mkey="$2"
    local escaped_path
    escaped_path="$(echo "$fpath" | sed "s/'/''/g")"
    sqlite3 "$DB" << EOF
INSERT OR REPLACE INTO uploads(path, media_key) VALUES ('$escaped_path', '$mkey');
DELETE FROM retry_queue WHERE path = '$escaped_path';
EOF
}

save_retry() {
    local fpath="$1"
    local attempts="$2"
    local escaped_path
    escaped_path="$(echo "$fpath" | sed "s/'/''/g")"
    sqlite3 "$DB" "INSERT OR REPLACE INTO retry_queue(path, attempts, last_attempt) VALUES ('$escaped_path', $attempts, datetime('now','localtime'));" 2>/dev/null || true
}

remove_retry() {
    local fpath="$1"
    local escaped_path
    escaped_path="$(echo "$fpath" | sed "s/'/''/g")"
    sqlite3 "$DB" "DELETE FROM retry_queue WHERE path = '$escaped_path';" 2>/dev/null || true
}

# Wait for file readiness (actively downloading/growing vs ready)
wait_for_file_ready() {
    local fpath="$1"
    [ ! -f "$fpath" ] && return 2 # NOT_FOUND

    local last_size=-1
    for ((i=0; i<30; i++)); do
        [ ! -f "$fpath" ] && return 2
        local size
        size=$(stat -c%s "$fpath" 2>/dev/null || stat -f%z "$fpath" 2>/dev/null || echo 0)

        if [ "$size" -lt "$MIN_BYTES" ]; then
            sleep 1
            continue
        fi

        if [ "$size" -ne "$last_size" ]; then
            last_size="$size"
            sleep 2
            continue
        fi

        # Check if another process holds write lock
        if command -v lsof >/dev/null 2>&1; then
            if lsof "$fpath" 2>/dev/null | grep -qE " (W|u) "; then
                sleep 2
                continue
            fi
        elif command -v fuser >/dev/null 2>&1; then
            if fuser -s "$fpath" 2>/dev/null; then
                sleep 2
                continue
            fi
        fi

        return 0 # READY
    done
    return 1 # LOCKED_OR_GROWING
}

invoke_upload() {
    local fpath="$1"
    [ ! -f "$fpath" ] && return
    case "$fpath" in
        */Modules/*) return ;;
        *.db|*.db-wal|*.db-shm|*.config|*.tmp|*.crdownload|*.part) return ;;
    esac

    local ext="${fpath##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    if ! echo "$ext" | grep -qE "$VALID_EXT"; then
        return
    fi

    if is_uploaded "$fpath"; then
        return
    fi

    local fname
    fname="$(basename "$fpath")"
    local size_bytes
    size_bytes=$(stat -c%s "$fpath" 2>/dev/null || stat -f%z "$fpath" 2>/dev/null || echo 0)
    local size_mb
    size_mb=$(awk -v b="$size_bytes" 'BEGIN { printf "%.2f", b/1048576 }')

    echo ""
    echo "[$(date '+%H:%M:%S')] Detected  : $fname (${size_mb} MB)"
    echo "             Path      : $fpath"

    wait_for_file_ready "$fpath"
    local status=$?
    if [ $status -eq 2 ]; then
        remove_retry "$fpath"
        return
    elif [ $status -eq 1 ]; then
        local prev
        prev=$(sqlite3 "$DB" "SELECT attempts FROM retry_queue WHERE path = '$(echo "$fpath" | sed "s/'/''/g")';" 2>/dev/null || echo 0)
        [ -z "$prev" ] && prev=0
        write_log "File still downloading/locked ($fname) - remaining in queue." "WARN"
        save_retry "$fpath" "$prev"
        return
    fi

    local start_time
    start_time=$(date +%s)
    local output
    output="$("${GOTOHP_CMD[@]}" upload "$fpath" 2>&1)"
    local exit_code=$?
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 0 ]; then
        local mkey
        mkey="$(echo "$output" | grep -o '"mediaKey": *"[^"]*"' | head -n1 | cut -d'"' -f4 || echo "")"
        echo "  [####################] 100% [OK] Uploaded in ${duration}s: $fname (${size_mb} MB)"
        write_log "SUCCESS | $fname (${size_mb} MB in ${duration}s)" "OK"
        save_upload "$fpath" "$mkey"
    else
        echo "  [--------------------] FAILED in ${duration}s: $fname"
        local attempts
        attempts=$(sqlite3 "$DB" "SELECT attempts FROM retry_queue WHERE path = '$(echo "$fpath" | sed "s/'/''/g")';" 2>/dev/null || echo 0)
        [ -z "$attempts" ] && attempts=0
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 3 ]; then
            write_log "GAVE UP after $attempts upload attempts: $fname" "ERROR"
            remove_retry "$fpath"
        else
            write_log "FAILED upload (attempt $attempts/3) - queued for retry: $fname" "WARN"
            save_retry "$fpath" "$attempts"
        fi
    fi
}

echo "=========================================================="
echo "  *  Google Photos Auto-Sync (Linux Edition)"
echo "  Location: $SCRIPT_DIR"
echo "  Database: $DB"
echo "=========================================================="
echo "  Watched Folders:"
for d in "${WATCH_DIRS[@]}"; do
    echo "    -> $d"
done
echo "=========================================================="

# Initial Startup Scan
echo "[Phase 1] Scanning for unrecorded files..."
file_count=0
while IFS= read -r -d '' file; do
    ext="${file##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    if echo "$ext" | grep -qE "$VALID_EXT" && ! is_uploaded "$file"; then
        file_count=$((file_count + 1))
        invoke_upload "$file"
    fi
done < <(find "${WATCH_DIRS[@]}" -type f -print0 2>/dev/null)

# Check retry queue for previous failures (< 3 attempts)
RETRY_LIST=$(sqlite3 "$DB" "SELECT path FROM retry_queue WHERE attempts < 3;" 2>/dev/null || true)
if [ -n "$RETRY_LIST" ]; then
    while IFS= read -r rfile; do
        if [ -f "$rfile" ] && ! is_uploaded "$rfile"; then
            file_count=$((file_count + 1))
            invoke_upload "$rfile"
        fi
    done <<< "$RETRY_LIST"
fi

if [ "$file_count" -eq 0 ]; then
    echo "[Phase 1] [OK] Everything backed up - zero new files."
else
    echo "[Phase 1] [OK] Startup sync complete ($file_count file(s))."
fi

# Phase 2 Real-Time Inotify Watcher
echo ""
echo "[Phase 2] Real-time watcher active."
echo "  Waiting for new downloads... Press Ctrl+C to stop."

cleanup() {
    echo ""
    echo "Stopping watcher..."
    pkill -P $$ 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM

inotifywait -m -r -e close_write,moved_to --format '%w%f' "${WATCH_DIRS[@]}" 2>/dev/null | while IFS= read -r new_path; do
    invoke_upload "$new_path"
done
