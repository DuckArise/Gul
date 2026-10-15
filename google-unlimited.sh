#!/usr/bin/env bash
# =====================================================================
# GoogleUnlimited - Native Linux Unified Manager
# Auto-Sync & Real-Time Watcher with Pixel Unlimited Backup
# =====================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="$SCRIPT_DIR/gphotos.db"
SERVICE_NAME="google-unlimited.service"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"

# Terminal Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

# ---------------------------------------------------------------------
# BINARY & CONFIG DISCOVERY
# ---------------------------------------------------------------------
get_gotohp_bin() {
    for cand in "$SCRIPT_DIR/gotohp-cli" "$SCRIPT_DIR/gotohp-cli_amd64" "$SCRIPT_DIR/gotohp-cli_arm64"; do
        if [ -x "$cand" ] || [ -f "$cand" ]; then
            chmod +x "$cand" 2>/dev/null || true
            echo "$cand"
            return 0
        fi
    done
    if command -v gotohp-cli >/dev/null 2>&1; then
        command -v gotohp-cli
        return 0
    fi
    echo ""
}

get_gotohp_cmd() {
    local bin
    bin="$(get_gotohp_bin)"
    if [ -z "$bin" ]; then
        echo "ERROR: gotohp-cli binary not found in $SCRIPT_DIR or system PATH." >&2
        echo "Please run: ./google-unlimited.sh setup" >&2
        exit 1
    fi
    if [ -f "$SCRIPT_DIR/gotohp.config" ]; then
        echo "$bin|--config|$SCRIPT_DIR/gotohp.config"
    else
        echo "$bin"
    fi
}

run_gotohp() {
    local cmd_spec
    cmd_spec="$(get_gotohp_cmd)"
    IFS='|' read -r -a cmd_arr <<< "$cmd_spec"
    "${cmd_arr[@]}" "$@"
}

# ---------------------------------------------------------------------
# DATABASE INITIALIZATION & LOGGING
# ---------------------------------------------------------------------
init_db() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] sqlite3 is not installed. Please run: ./google-unlimited.sh setup${NC}" >&2
        exit 1
    fi

    sqlite3 "$DB" >/dev/null << 'EOF'
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

    # Dual-boot cross-platform tracking migration
    sqlite3 "$DB" "ALTER TABLE uploads ADD COLUMN file_name TEXT;" 2>/dev/null || true
    sqlite3 "$DB" "ALTER TABLE uploads ADD COLUMN file_size INTEGER;" 2>/dev/null || true
    sqlite3 "$DB" "CREATE INDEX IF NOT EXISTS idx_uploads_file ON uploads(file_name, file_size);" 2>/dev/null || true
}

write_log() {
    local msg="$1"
    local level="${2:-INFO}"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local escaped_msg="${msg//\'/\'\'}"
    sqlite3 "$DB" "INSERT INTO logs(level, message) VALUES ('$level', '$escaped_msg');" 2>/dev/null || true
    echo "[$ts][$level] $msg"
}

is_uploaded() {
    local fpath="$1"
    local fname="${2:-$(basename "$fpath")}"
    local fsize="${3:-0}"
    local escaped_path="${fpath//\'/\'\'}"
    local escaped_name="${fname//\'/\'\'}"

    local count
    if [ "$fsize" -gt 0 ]; then
        count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM uploads WHERE path = '$escaped_path' OR (file_name = '$escaped_name' AND file_size = $fsize AND file_size > 0);" 2>/dev/null || echo 0)
    else
        count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM uploads WHERE path = '$escaped_path';" 2>/dev/null || echo 0)
    fi
    [ -n "$count" ] && [ "$count" -gt 0 ]
}

save_upload() {
    local fpath="$1"
    local mkey="$2"
    local fname="${3:-$(basename "$fpath")}"
    local fsize="${4:-0}"
    local escaped_path="${fpath//\'/\'\'}"
    local escaped_name="${fname//\'/\'\'}"

    sqlite3 "$DB" << EOF
INSERT OR REPLACE INTO uploads(path, media_key, file_name, file_size) VALUES ('$escaped_path', '$mkey', '$escaped_name', $fsize);
DELETE FROM retry_queue WHERE path = '$escaped_path';
EOF
}

save_retry() {
    local fpath="$1"
    local attempts="$2"
    local escaped_path="${fpath//\'/\'\'}"
    sqlite3 "$DB" "INSERT OR REPLACE INTO retry_queue(path, attempts, last_attempt) VALUES ('$escaped_path', $attempts, datetime('now','localtime'));" 2>/dev/null || true
}

remove_retry() {
    local fpath="$1"
    local escaped_path="${fpath//\'/\'\'}"
    sqlite3 "$DB" "DELETE FROM retry_queue WHERE path = '$escaped_path';" 2>/dev/null || true
}

# ---------------------------------------------------------------------
# ACTION: SETUP & DEPENDENCIES
# ---------------------------------------------------------------------
do_setup() {
    echo ""
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "${GREEN}  *  GoogleUnlimited - Linux Setup & Dependency Check${NC}"
    echo -e "${GRAY}  Location: $SCRIPT_DIR${NC}"
    echo -e "${CYAN}==========================================================${NC}"

    local missing=()
    command -v inotifywait >/dev/null 2>&1 || missing+=("inotify-tools")
    command -v sqlite3 >/dev/null 2>&1 || missing+=("sqlite3")
    command -v curl >/dev/null 2>&1 || missing+=("curl")

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}[Setup] Installing required packages: ${missing[*]}...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y "${missing[@]}"
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y "${missing[@]}"
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -Sy --noconfirm "${missing[@]}"
        elif command -v zypper >/dev/null 2>&1; then
            sudo zypper install -y "${missing[@]}"
        else
            echo -e "${RED}[WARN] Could not identify package manager. Please install manually: ${missing[*]}${NC}"
        fi
    else
        echo -e "${GREEN}[OK] Required packages (inotify-tools, sqlite3, curl) are already installed.${NC}"
    fi

    # Verify/download gotohp-cli
    local arch
    arch="$(uname -m)"
    local target_bin="$SCRIPT_DIR/gotohp-cli_amd64"
    if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
        target_bin="$SCRIPT_DIR/gotohp-cli_arm64"
        if [ ! -f "$target_bin" ]; then
            echo -e "${YELLOW}[Setup] Downloading gotohp-cli for ARM64...${NC}"
            curl -fSL "https://github.com/xob0t/gotohp/releases/latest/download/gotohp-cli_arm64" -o "$target_bin"
        fi
    elif [ ! -f "$target_bin" ]; then
        echo -e "${YELLOW}[Setup] Downloading gotohp-cli for x86_64...${NC}"
        curl -fSL "https://github.com/xob0t/gotohp/releases/latest/download/gotohp-cli_amd64" -o "$target_bin"
    fi

    chmod +x "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/gotohp-cli* 2>/dev/null || true
    echo -e "${GREEN}[OK] Execution permissions set.${NC}"

    # Check credentials
    local creds_out
    creds_out="$(run_gotohp creds list 2>&1 || true)"
    if echo "$creds_out" | grep -q "\*"; then
        echo -e "${GREEN}[OK] Active Google Photos account detected.${NC}"
    else
        echo ""
        echo -e "${YELLOW}==========================================================${NC}"
        echo -e "${YELLOW}  ACTION REQUIRED: Sign In to Google Photos${NC}"
        echo -e "${YELLOW}==========================================================${NC}"
        echo "  1. On any browser, open Google Embedded Setup sign-in."
        echo "  2. Retrieve your 'oauth_token' cookie from DevTools."
        local cfg_hint=""
        if [ -f "$SCRIPT_DIR/gotohp.config" ]; then
            cfg_hint="--config gotohp.config "
        fi
        echo "  3. Run:"
        echo "     ./google-unlimited.sh ${cfg_hint}creds add \"<oauth_token>\""
        echo -e "${YELLOW}==========================================================${NC}"
    fi

    echo ""
    echo -e "${GREEN}[Setup] Complete! You can now run: ./google-unlimited.sh${NC}"
}

# ---------------------------------------------------------------------
# ACTION: STATUS
# ---------------------------------------------------------------------
do_status() {
    init_db
    echo ""
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "${GREEN}  *  Google Photos Sync Status${NC}"
    echo -e "${GRAY}  Database: $DB${NC}"
    echo -e "${CYAN}==========================================================${NC}"

    local total_count
    total_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM uploads;" 2>/dev/null || echo 0)
    local retry_count
    retry_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM retry_queue;" 2>/dev/null || echo 0)

    echo -e "  Total Uploaded Files : ${YELLOW}$total_count${NC}"
    if [ "$retry_count" -gt 0 ]; then
        echo -e "  Pending Retries      : ${RED}$retry_count${NC}"
    else
        echo -e "  Pending Retries      : ${GREEN}0${NC}"
    fi

    echo ""
    echo -e "${CYAN}  Last 10 Uploads:${NC}"
    local last_uploads
    last_uploads=$(sqlite3 "$DB" "SELECT uploaded_at, path FROM uploads ORDER BY uploaded_at DESC LIMIT 10;" 2>/dev/null || true)
    if [ -n "$last_uploads" ]; then
        while IFS='|' read -r uploaded_at fpath; do
            fname="${fpath##*[/\\]}"
            echo -e "    ${GRAY}[$uploaded_at]${NC} $fname"
        done <<< "$last_uploads"
    else
        echo -e "    ${GRAY}(None yet)${NC}"
    fi

    if [ "$retry_count" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}  Pending Retries in Queue:${NC}"
        local retries
        retries=$(sqlite3 "$DB" "SELECT path, attempts FROM retry_queue;" 2>/dev/null || true)
        while IFS='|' read -r fpath attempts; do
            fname=$(basename "$fpath")
            echo -e "    ${YELLOW}$fname (attempt $attempts)${NC}"
        done <<< "$retries"
    fi

    echo -e "${CYAN}==========================================================${NC}"
    echo ""
}

# ---------------------------------------------------------------------
# ACTION: ACTIVITY LOGS
# ---------------------------------------------------------------------
do_logs() {
    init_db
    echo ""
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "${GREEN}  *  Google Photos Sync - Activity Logs (Last 30)${NC}"
    echo -e "${GRAY}  Database: $DB${NC}"
    echo -e "${CYAN}==========================================================${NC}"

    local log_rows
    log_rows=$(sqlite3 "$DB" "SELECT timestamp, level, message FROM (SELECT id, timestamp, level, message FROM logs ORDER BY id DESC LIMIT 30) ORDER BY id ASC;" 2>/dev/null || true)

    if [ -n "$log_rows" ]; then
        while IFS='|' read -r timestamp level message; do
            local color="$GRAY"
            case "$level" in
                "OK")    color="$GREEN" ;;
                "WARN")  color="$YELLOW" ;;
                "ERROR") color="$RED" ;;
            esac
            echo -e "[$timestamp][${color}$level${NC}] $message"
        done <<< "$log_rows"
    else
        echo -e "  ${GRAY}No activity logs found.${NC}"
    fi

    echo -e "${CYAN}==========================================================${NC}"
    echo ""
}

# ---------------------------------------------------------------------
# ACTION: STOP WATCHER
# ---------------------------------------------------------------------
do_stop() {
    echo -e "${CYAN}Stopping Google Photos background watcher...${NC}"
    local stopped=0

    # Stop processes matching google-unlimited.sh or watch_and_upload.sh
    local pids
    pids=$(pgrep -f "google-unlimited.sh|watch_and_upload.sh" || true)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if [ "$pid" != "$$" ]; then
                kill "$pid" 2>/dev/null || true
                echo -e "${GREEN}[OK] Terminated watcher PID $pid${NC}"
                stopped=1
            fi
        done
    fi

    # Terminate orphaned inotifywait listeners
    local ipids
    ipids=$(pgrep -f "inotifywait -m -r -e close_write,moved_to" || true)
    if [ -n "$ipids" ]; then
        for ipid in $ipids; do
            kill "$ipid" 2>/dev/null || true
            echo -e "${GREEN}[OK] Stopped inotifywait listener PID $ipid${NC}"
            stopped=1
        done
    fi

    # Terminate systemd user service if active
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
            echo -e "${GREEN}[OK] Stopped systemd user service '$SERVICE_NAME'${NC}"
            stopped=1
        fi
    fi

    if [ "$stopped" -eq 1 ]; then
        echo -e "${GREEN}All background watcher instances have been stopped.${NC}"
    else
        echo -e "${YELLOW}No active watcher instances were found running.${NC}"
    fi
}

# ---------------------------------------------------------------------
# ACTION: ENABLE STARTUP (systemd)
# ---------------------------------------------------------------------
do_enable_startup() {
    echo -e "${CYAN}Enabling Google Photos Auto-Sync on startup (Linux systemd)...${NC}"

    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] systemctl not found. Your Linux distribution does not appear to use systemd.${NC}"
        echo "You can manually add '$SCRIPT_DIR/google-unlimited.sh watch' to your desktop autostart or cron (@reboot)."
        exit 1
    fi

    mkdir -p "$USER_SYSTEMD_DIR"

    cat << EOF > "$USER_SYSTEMD_DIR/$SERVICE_NAME"
[Unit]
Description=Google Photos Unlimited Auto-Sync Watcher
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/google-unlimited.sh watch
Restart=on-failure
RestartSec=10
KillMode=mixed

[Install]
WantedBy=default.target
EOF

    echo -e "${GREEN}[OK] Service unit created at: $USER_SYSTEMD_DIR/$SERVICE_NAME${NC}"

    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE_NAME"
    systemctl --user restart "$SERVICE_NAME"

    if command -v loginctl >/dev/null 2>&1; then
        local current_user="${USER:-$(id -un 2>/dev/null || whoami 2>/dev/null || echo "")}"
        if [ -n "$current_user" ]; then
            loginctl enable-linger "$current_user" 2>/dev/null || true
        fi
    fi

    echo ""
    echo -e "${GREEN}==========================================================${NC}"
    echo -e "${GREEN}  *  Auto-Sync has been enabled for Linux startup!${NC}"
    echo -e "${GREEN}==========================================================${NC}"
    echo "Status check:    systemctl --user status $SERVICE_NAME"
    echo "View logs:       ./google-unlimited.sh logs"
    echo "Disable anytime: ./google-unlimited.sh disable"
    echo ""
}

# ---------------------------------------------------------------------
# ACTION: DISABLE STARTUP (systemd)
# ---------------------------------------------------------------------
do_disable_startup() {
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
}

# ---------------------------------------------------------------------
# ACTION: CORE WATCHER
# ---------------------------------------------------------------------
wait_for_file_ready() {
    local fpath="$1"
    local min_bytes=10240
    [ ! -f "$fpath" ] && return 2

    local last_size=-1
    for ((i=0; i<30; i++)); do
        [ ! -f "$fpath" ] && return 2
        local size
        size=$(stat -c%s "$fpath" 2>/dev/null || stat -f%z "$fpath" 2>/dev/null || echo 0)

        if [ "$size" -lt "$min_bytes" ]; then
            sleep 1
            continue
        fi

        if [ "$size" -ne "$last_size" ]; then
            last_size="$size"
            sleep 2
            continue
        fi

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

        return 0
    done
    return 1
}

invoke_upload() {
    local fpath="$1"
    [ -d "$fpath" ] && return
    [ ! -f "$fpath" ] && return
    case "$fpath" in
        */Modules/*) return ;;
        *.db|*.db-wal|*.db-shm|*.config|*.tmp|*.crdownload|*.part) return ;;
    esac

    local ext="${fpath##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    local valid_ext="^(jpg|jpeg|png|heic|webp|gif|mp4|mov|mkv|avi|dng)$"
    if ! echo "$ext" | grep -qE "$valid_ext"; then
        return
    fi

    local fname
    fname="$(basename "$fpath")"
    local size_bytes
    size_bytes=$(stat -c%s "$fpath" 2>/dev/null || stat -f%z "$fpath" 2>/dev/null || echo 0)
    local size_mb
    size_mb=$(awk -v b="$size_bytes" 'BEGIN { printf "%.2f", b/1048576 }')

    # Dual-boot cross-platform deduplication check
    if is_uploaded "$fpath" "$fname" "$size_bytes"; then
        return
    fi

    echo ""
    echo "[$(date '+%H:%M:%S')] Detected  : $fname (${size_mb} MB)"
    echo "             Path      : $fpath"

    wait_for_file_ready "$fpath"
    local status=$?
    local escaped_path="${fpath//\'/\'\'}"

    if [ $status -eq 2 ]; then
        remove_retry "$fpath"
        return
    elif [ $status -eq 1 ]; then
        local prev
        prev=$(sqlite3 "$DB" "SELECT attempts FROM retry_queue WHERE path = '$escaped_path';" 2>/dev/null || echo 0)
        [ -z "$prev" ] && prev=0
        write_log "File still downloading/locked ($fname) - remaining in queue." "WARN"
        save_retry "$fpath" "$prev"
        return
    fi

    local start_time
    start_time=$(date +%s)
    local output
    output="$(run_gotohp upload "$fpath" 2>&1)"
    local exit_code=$?
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 0 ]; then
        local mkey
        mkey="$(echo "$output" | grep -o '"mediaKey": *"[^"]*"' | head -n1 | cut -d'"' -f4 || echo "")"
        echo "  [####################] 100% [OK] Uploaded in ${duration}s: $fname (${size_mb} MB)"
        write_log "SUCCESS | $fname (${size_mb} MB in ${duration}s)" "OK"
        save_upload "$fpath" "$mkey" "$fname" "$size_bytes"
    else
        echo "  [--------------------] FAILED in ${duration}s: $fname"
        local attempts
        attempts=$(sqlite3 "$DB" "SELECT attempts FROM retry_queue WHERE path = '$escaped_path';" 2>/dev/null || echo 0)
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

do_watch() {
    init_db

    # Check credentials
    local creds_check
    creds_check="$(run_gotohp creds list 2>&1 || true)"
    if ! echo "$creds_check" | grep -q "\*"; then
        echo ""
        echo -e "${RED}==========================================================${NC}"
        echo -e "${YELLOW}  ACTION REQUIRED: No Google Account Logged In!${NC}"
        echo -e "${RED}==========================================================${NC}"
        echo "  Please sign in by running:"
        echo "    ./google-unlimited.sh creds add \"<oauth_token>\""
        echo -e "${RED}==========================================================${NC}"
        exit 1
    fi

    # Discover watched folders
    local watch_dirs=()
    for folder in "$HOME/Downloads" "$HOME/Pictures" "$HOME/Desktop" "$HOME/Documents" "$HOME/Music" "$HOME/Videos"; do
        if [ -d "$folder" ]; then
            watch_dirs+=("$folder")
        fi
    done

    if [ ${#watch_dirs[@]} -eq 0 ]; then
        mkdir -p "$HOME/Pictures"
        watch_dirs=("$HOME/Pictures")
    fi

    echo ""
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "${GREEN}  *  GoogleUnlimited - Linux Watcher${NC}"
    echo -e "${GRAY}  Location: $SCRIPT_DIR${NC}"
    echo -e "${GRAY}  Database: $DB${NC}"
    echo -e "${CYAN}==========================================================${NC}"
    echo "  Watched Folders:"
    for d in "${watch_dirs[@]}"; do
        echo "    -> $d"
    done
    echo -e "${CYAN}==========================================================${NC}"

    # Phase 1: Startup Scan
    echo -e "${CYAN}[Phase 1] Scanning for unrecorded files...${NC}"
    local valid_ext="^(jpg|jpeg|png|heic|webp|gif|mp4|mov|mkv|avi|dng)$"
    local file_count=0
    while IFS= read -r -d '' file; do
        local ext="${file##*.}"
        ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
        if echo "$ext" | grep -qE "$valid_ext"; then
            local fname
            fname="$(basename "$file")"
            local size_bytes
            size_bytes=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
            if ! is_uploaded "$file" "$fname" "$size_bytes"; then
                file_count=$((file_count + 1))
                invoke_upload "$file"
            fi
        fi
    done < <(find "${watch_dirs[@]}" -type f -print0 2>/dev/null)

    # Check retry queue for previous failures
    local retry_list
    retry_list=$(sqlite3 "$DB" "SELECT path FROM retry_queue WHERE attempts < 3;" 2>/dev/null || true)
    if [ -n "$retry_list" ]; then
        while IFS= read -r rfile; do
            if [ -f "$rfile" ]; then
                local rfname
                rfname="$(basename "$rfile")"
                local rsize_bytes
                rsize_bytes=$(stat -c%s "$rfile" 2>/dev/null || stat -f%z "$rfile" 2>/dev/null || echo 0)
                if ! is_uploaded "$rfile" "$rfname" "$rsize_bytes"; then
                    file_count=$((file_count + 1))
                    invoke_upload "$rfile"
                fi
            fi
        done <<< "$retry_list"
    fi

    if [ "$file_count" -eq 0 ]; then
        echo -e "${GREEN}[Phase 1] [OK] Everything backed up - zero new files.${NC}"
    else
        echo -e "${GREEN}[Phase 1] [OK] Startup sync complete ($file_count file(s)).${NC}"
    fi

    # Phase 2: Inotify Watcher
    echo ""
    echo -e "${YELLOW}[Phase 2] Real-time watcher active.${NC}"
    echo "  Waiting for new media... Press Ctrl+C to stop."

    # Run inotifywait pipeline in the background so parent can trap signals cleanly
    inotifywait -m -r -e close_write,moved_to,create --format '%w%f' "${watch_dirs[@]}" 2>/dev/null | while IFS= read -r new_path; do
        invoke_upload "$new_path"
    done &
    local watcher_pid=$!

    cleanup() {
        # Untrap immediately to prevent recursive signal/exit loops
        trap - SIGINT SIGTERM EXIT
        echo ""
        echo "Stopping watcher..."
        if [ -n "${watcher_pid:-}" ]; then
            pkill -P "$watcher_pid" 2>/dev/null || true
            kill "$watcher_pid" 2>/dev/null || true
        fi
        exit 0
    }
    trap cleanup SIGINT SIGTERM

    wait "$watcher_pid" 2>/dev/null || true
}

# ---------------------------------------------------------------------
# INTERACTIVE TERMINAL MENU
# ---------------------------------------------------------------------
show_menu() {
    clear 2>/dev/null || true
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "${GREEN}  *  GoogleUnlimited - Linux Manager${NC}"
    echo -e "${CYAN}==========================================================${NC}"
    echo "  [1] Start Live Watcher (Foreground)"
    echo "  [2] Check Backup Status"
    echo "  [3] View Activity Logs"
    echo "  [4] Run Setup & Dependency Installer"
    echo "  [5] Enable Auto-Start on Boot (systemd)"
    echo "  [6] Disable Auto-Start on Boot"
    echo "  [7] Stop Background Watcher"
    echo "  [0] Exit"
    echo -e "${CYAN}==========================================================${NC}"
    read -rp "Select an option [1-7, Default: 1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        1) do_watch ;;
        2) do_status ;;
        3) do_logs ;;
        4) do_setup ;;
        5) do_enable_startup ;;
        6) do_disable_startup ;;
        7) do_stop ;;
        0) exit 0 ;;
        *) echo "Invalid option"; sleep 1; show_menu ;;
    esac
}

show_help() {
    echo "Usage: ./google-unlimited.sh [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  watch             Start live real-time sync watcher (default)"
    echo "  status            Check upload count and pending retries"
    echo "  logs              View last 30 sync activity log entries"
    echo "  setup             Install dependencies (inotify-tools, sqlite3)"
    echo "  enable            Enable auto-start on boot via systemd"
    echo "  disable           Disable systemd auto-start service"
    echo "  stop              Stop running background watcher instances"
    echo "  creds             Pass creds commands directly to gotohp-cli"
    echo "  menu              Open interactive terminal menu"
    echo "  help              Show this help message"
}

# ---------------------------------------------------------------------
# CLI DISPATCHER
# ---------------------------------------------------------------------
CMD="${1:-}"
case "$CMD" in
    watch|--watch|run|--run)
        do_watch
        ;;
    status|--status|-s)
        do_status
        ;;
    logs|--logs|-l)
        do_logs
        ;;
    setup|--setup)
        do_setup
        ;;
    enable|enable-startup|--enable)
        do_enable_startup
        ;;
    disable|disable-startup|--disable)
        do_disable_startup
        ;;
    stop|--stop)
        do_stop
        ;;
    creds)
        shift
        run_gotohp creds "$@"
        ;;
    menu|--menu)
        show_menu
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        if [ -t 0 ]; then
            show_menu
        else
            do_watch
        fi
        ;;
    *)
        echo "Unknown command: $CMD"
        show_help
        exit 1
        ;;
esac
