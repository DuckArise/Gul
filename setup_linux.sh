#!/usr/bin/env bash
# =====================================================================
# Google Photos Unlimited Auto-Sync - Linux Dependency & Setup Script
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================================="
echo "  *  Google Photos Auto-Sync - Linux Setup"
echo "  Location: $SCRIPT_DIR"
echo "=========================================================="

# 1. Install required tools (inotify-tools, sqlite3, curl)
MISSING_PKGS=()
if ! command -v inotifywait >/dev/null 2>&1; then
    MISSING_PKGS+=("inotify-tools")
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
    MISSING_PKGS+=("sqlite3")
fi
if ! command -v curl >/dev/null 2>&1; then
    MISSING_PKGS+=("curl")
fi

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "[Setup] Installing required packages: ${MISSING_PKGS[*]}..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y "${MISSING_PKGS[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "${MISSING_PKGS[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm "${MISSING_PKGS[@]}"
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y "${MISSING_PKGS[@]}"
    else
        echo "[WARN] Could not identify package manager. Please manually install: ${MISSING_PKGS[*]}"
    fi
else
    echo "[OK] Required dependencies (inotify-tools, sqlite3, curl) are already installed."
fi

# 2. Verify / Download native Linux gotohp binary
ARCH="$(uname -m)"
GOTOHP_BIN="$SCRIPT_DIR/gotohp-cli_amd64"

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    GOTOHP_BIN="$SCRIPT_DIR/gotohp-cli_arm64"
    if [ ! -f "$GOTOHP_BIN" ]; then
        echo "[Setup] Downloading gotohp-cli for ARM64..."
        curl -fSL "https://github.com/xob0t/gotohp/releases/latest/download/gotohp-cli_arm64" -o "$GOTOHP_BIN"
    fi
elif [ ! -f "$GOTOHP_BIN" ]; then
    echo "[Setup] Downloading gotohp-cli for x86_64..."
    curl -fSL "https://github.com/xob0t/gotohp/releases/latest/download/gotohp-cli_amd64" -o "$GOTOHP_BIN"
fi

# Make scripts and binaries executable
chmod +x "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/gotohp-cli* 2>/dev/null || true
echo "[OK] Execution permissions set."

# 3. Check Google Photos credentials
if [ -f "$SCRIPT_DIR/gotohp.config" ]; then
    GOTOHP_CMD=("$GOTOHP_BIN" "--config" "$SCRIPT_DIR/gotohp.config")
else
    GOTOHP_CMD=("$GOTOHP_BIN")
fi

CREDS_OUTPUT="$("${GOTOHP_CMD[@]}" creds list 2>&1 || true)"
if echo "$CREDS_OUTPUT" | grep -q "\*"; then
    echo "[OK] Active Google Photos account detected."
else
    echo ""
    echo "=========================================================="
    echo "  ACTION REQUIRED: Sign In to Google Photos"
    echo "=========================================================="
    echo "  1. On any browser, open Google Embedded Setup sign-in."
    echo "  2. Retrieve your 'oauth_token' cookie from DevTools."
    CONFIG_HINT=""
    if [ -f "$SCRIPT_DIR/gotohp.config" ]; then
        CONFIG_HINT="--config gotohp.config "
    fi
    echo "  3. Run:"
    echo "     ./$([ -f "$GOTOHP_BIN" ] && basename "$GOTOHP_BIN" || echo "gotohp-cli_amd64") ${CONFIG_HINT}creds add \"<oauth_token>\""
    echo "=========================================================="
fi

echo ""
echo "[Setup] Done! You can now run:"
echo "  ./watch_and_upload.sh      (Interactive real-time sync)"
echo "  ./check_status.sh          (View upload stats)"
echo "  ./view_logs.sh             (View sync logs)"
echo "  ./stop_watcher.sh          (Stop running watcher)"
echo ""
echo "To auto-start on boot via systemd, simply run:"
echo "  ./enable_startup.sh        (Auto-registers systemd user service)"
echo "  ./disable_startup.sh       (To remove startup service)"

