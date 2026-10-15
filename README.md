# GoogleUnlimited

> **Zero-Quota, Unlimited Google Photos Auto-Sync for Windows & Linux**  
> Native background watcher that automatically uploads photos and videos with **Google Pixel original quality unlimited backup** — without WSL, WSA, Android emulators, or Morphe crashes.

<p align="center">
  <img src="reddit_showcase.jpg" alt="GoogleUnlimited Showcase" width="100%" />
</p>

---

## Features

- **Unlimited Google Photos Backup**: Spoofs Google Pixel mobile upload API ([`xob0t/gotohp`](https://github.com/xob0t/gotohp)) so all uploaded photos and videos consume **0 bytes of Google Drive / Google One storage**.
- **Cross-Platform (Windows & Linux)**: Native PowerShell engine on Windows and native POSIX Bash + `inotify` engine on Linux. No emulators or virtual machines.
- **Dual-Boot Interoperability**: Windows and Linux scripts share the exact same SQLite database schema (`gphotos.db`), allowing shared partition or dual-boot setups to seamlessly avoid duplicate uploads.
- **Portable & Zero-Install**: Runs from any directory, on any PC or USB drive without system-wide installation.
- **Real-Time Auto-Sync**: Monitors standard user folders instantly when files are downloaded or saved, with debounce protection for active downloads.
- **Embedded SQLite Tracking**: Tracks every upload in `gphotos.db` — zero duplicate re-uploads, crash-resilient with automatic retry queues.
- **Live Terminal Progress Bar**: Interactive runner with real-time dynamic progress bar, elapsed timer, and file size indicator.
- **Background Auto-Start**: 
  - Windows: 1-click installer (`EnableStartup.bat`) or silent VBScript launcher (`StartPhotosWatcher.vbs`).
  - Linux: 1-click systemd user unit installer (`./enable_startup.sh`).

---

## Directory Structure

```text
GoogleUnlimited/
│
├── Modules/
│   └── PSSQLite/             # Bundled portable SQLite engine for Windows PowerShell
│
├── gotohp-cli-x64.exe        # Windows 64-bit CLI uploader with Pixel spoofing
├── gotohp-x64.exe            # Windows desktop GUI for one-click Google OAuth sign-in
├── gotohp-cli_amd64          # Native Linux x86_64 ELF binary
│
│   # --- Windows Scripts ---
├── RunWatcher.bat            # Windows interactive launcher (shows live progress)
├── StartPhotosWatcher.vbs    # Windows silent background launcher (zero window)
├── EnableStartup.bat         # Windows 1-click auto-start on boot installer
├── DisableStartup.bat        # Windows 1-click auto-start uninstaller
├── StopWatcher.bat           # Stops running Windows background watcher
├── ViewLogs.bat              # Displays recent sync activity logs
├── CheckStatus.bat           # Shows upload statistics and retry queue
├── WatchAndUpload.ps1        # Core Windows PowerShell orchestrator
│
│   # --- Linux Scripts ---
├── setup_linux.sh            # Linux 1-command installer (dependencies + binary + chmod)
├── watch_and_upload.sh       # Core Linux Bash watcher (inotify + SQLite engine)
├── enable_startup.sh         # Linux 1-click systemd user auto-start installer
├── disable_startup.sh        # Linux 1-click systemd user auto-start uninstaller
├── stop_watcher.sh           # Stops running Linux background watcher & inotifywait
├── view_logs.sh              # Linux terminal activity log viewer with colors
├── check_status.sh           # Linux terminal status & queue viewer
├── google-unlimited.service  # systemd user service unit template
│
├── .gitignore                # Protects credentials, tokens, and personal databases
└── README.md                 # Documentation
```

---

## Windows Setup & Usage

### 1. Download or Clone
```cmd
git clone https://github.com/shishir0x/GoogleUnlimited.git
```

### 2. Sign In to Google Photos (One-Time)
1. Double-click **`gotohp-x64.exe`** and click **Add Google account**.
2. Click **Open Google sign-in** and sign in with your Google account.
3. Sign in on the Google Embedded Setup page and click **I agree**.  
   *(Note: The page buffering indefinitely is completely normal and expected).*
4. Open browser Developer Tools (**F12**):
   - Go to **Application** tab (Chrome/Edge/Brave) or **Storage** tab (Firefox).
   - Under **Cookies**, click `https://accounts.google.com`.
   - Copy the value of the **`oauth_token`** cookie.
5. In `gotohp`, paste the token and click **Connect account**.
6. Once connected, your credentials are saved locally. Close the GUI.

### 3. Run on Windows
- **Interactive Mode**: Double-click **`RunWatcher.bat`** (shows live progress bars).
- **Background Mode**: Double-click **`StartPhotosWatcher.vbs`** (silent, zero window).
- **Auto-Start on Boot**: Double-click **`EnableStartup.bat`** (or **`DisableStartup.bat`** to remove).
- **Check Status / Logs**: Double-click **`CheckStatus.bat`** or **`ViewLogs.bat`**.
- **Stop Watcher**: Double-click **`StopWatcher.bat`**.

---

## Linux Setup & Usage

GoogleUnlimited runs natively on any Linux distribution (Ubuntu, Debian, Fedora, Arch Linux, openSUSE, etc.) using `inotify-tools`, `sqlite3`, and the native Linux `gotohp` binary.

### 1. Clone the Repository
```bash
git clone https://github.com/shishir0x/GoogleUnlimited.git
cd GoogleUnlimited
```

### 2. One-Command Setup
Run the automated Linux setup script:
```bash
chmod +x setup_linux.sh
./setup_linux.sh
```
What this does automatically:
- Detects your package manager (`apt`, `dnf`, `pacman`, `zypper`) and installs `inotify-tools`, `sqlite3`, and `curl` if not already installed.
- Detects your architecture (`x86_64` or `aarch64` / `arm64`) and ensures the proper native binary is ready.
- Sets execute permissions (`chmod +x`) on all scripts.

### 3. Sign In (One-Time)
Run:
```bash
./gotohp-cli_amd64 creds add "<oauth_token>"
```
*(If on ARM64, use `./gotohp-cli_arm64 creds add "<oauth_token>"`)*

To get the `oauth_token`:
1. In any web browser, open the Google Embedded Setup sign-in page.
2. Sign in and open browser Developer Tools (**F12**).
3. Under **Cookies** -> `https://accounts.google.com`, copy the **`oauth_token`** cookie value.

### 4. Run on Linux
- **Interactive Mode**:
  ```bash
  ./watch_and_upload.sh
  ```
  Runs the startup scan (Phase 1) followed by real-time `inotify` monitoring (Phase 2).

- **Auto-Start on Boot (systemd user service)**:
  ```bash
  ./enable_startup.sh
  ```
  This creates, enables, and immediately starts a `systemd` user service (`google-unlimited.service`) that automatically launches the sync watcher on system boot and keeps it running quietly in the background.

- **Check Status**:
  ```bash
  ./check_status.sh
  ```
  Displays total uploaded files, pending retries, and the last 10 uploads.

- **View Activity Logs**:
  ```bash
  ./view_logs.sh
  ```
  Displays the last 30 timestamped activity events with color-coded log levels (`OK`, `WARN`, `ERROR`).

- **Stop Watcher**:
  ```bash
  ./stop_watcher.sh
  ```
  Stops any running interactive or background watcher instances.

- **Disable Startup Service**:
  ```bash
  ./disable_startup.sh
  ```

---

## Monitored Folders (Dynamic Resolution)

The watcher monitors standard user directories across both operating systems:
- `Downloads`
- `Pictures`
- `Desktop`
- `Documents`
- `Music`
- `Videos`

On Windows, directories are dynamically resolved via Windows Shell API & Registry (handling custom drive paths and OneDrive redirection). On Linux, standard XDG user directories are automatically resolved.

### Supported File Extensions
- **Images**: `.jpg`, `.jpeg`, `.png`, `.heic`, `.webp`, `.gif`, `.dng`
- **Videos**: `.mp4`, `.mov`, `.mkv`, `.avi`

---

## Privacy & Security

- **Direct Connections Only**: Every API request and media upload connects directly from your machine to official Google Photos endpoints (`photoslibrary.googleapis.com`). No intermediate or third-party servers are involved.
- **Local Credentials**: Authentication tokens and config files stay strictly on your local machine.
- **Git Protection**: The `.gitignore` file excludes:
  - Database files (`gphotos.db`, `*.db`, `*.db-wal`, `*.db-shm`)
  - Personal config files and tokens (`gotohp.config`, `*.config`, `*.token`)
  - Log files and temporary cache
  Your personal file history and login tokens are **never** committed or pushed to Git.
- **Zero Telemetry**: No tracking, analytics, or external telemetry of any kind.

---

## Troubleshooting & Issues

If you encounter any bugs, unexpected behavior, or need help:
- Run `./check_status.sh` (Linux) or `CheckStatus.bat` (Windows) to check queue and database status.
- Run `./view_logs.sh` (Linux) or `ViewLogs.bat` (Windows) to inspect error details.
- Please submit an issue on the GitHub repository:  
  👉 **[Report an Issue on GitHub](https://github.com/shishir0x/GoogleUnlimited/issues)**

---

## License & Credits

- Core Pixel upload engine powered by [`xob0t/gotohp`](https://github.com/xob0t/gotohp).
- Windows SQLite integration powered by `PSSQLite`.
