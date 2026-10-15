# GoogleUnlimited

> **Zero-Quota, Unlimited Google Photos Auto-Sync for Windows**  
> Native Windows background watcher that automatically uploads photos and videos with **Pixel original quality unlimited backup** — without WSL, WSA, Android emulators, or Morphe crashes.

<p align="center">
  <img src="reddit_showcase.jpg" alt="GoogleUnlimited Showcase" width="100%" />
</p>

---

## Features

- **Unlimited Google Photos Backup**: Spoofs Google Pixel mobile upload API (`xob0t/gotohp`) so all uploaded photos and videos consume **0 bytes of Google Drive / Google One storage**.
- **100% Native Windows**: No WSL2, no Windows Subsystem for Android, no virtual machines, no Morphe/Tensor NPU emulation crashes.
- **Portable & Zero-Install**: Runs from any directory, on any Windows PC (Windows 10 / 11), on both Windows PowerShell 5.1 and PowerShell 7+.
- **Real-Time Auto-Sync**: Monitors standard user folders instantly when files are downloaded or saved, plus runs periodic sweeps every 30 seconds.
- **Embedded SQLite Tracking**: Tracks every upload in `gphotos.db` — zero duplicate re-uploads, crash-resilient with automatic retry queues.
- **Live Terminal Progress Bar**: Interactive runner with real-time dynamic progress bar, elapsed timer, and file size indicator.
- **Silent Background Launcher**: One-click VBScript launcher to run silently in the background on startup with no terminal window.

---

## Directory Structure

```text
GoogleUnlimited/
│
├── Modules/
│   └── PSSQLite/             # Bundled portable SQLite engine (x86, x64, .NET Framework & Core)
│
├── gotohp-cli-x64.exe        # High-performance CLI uploader with Pixel spoofing
├── gotohp-x64.exe            # Desktop GUI for easy one-click Google OAuth sign-in
│
├── RunWatcher.bat            # Interactive launcher (shows live terminal & animated progress)
├── StartPhotosWatcher.vbs    # Background launcher (runs silently with zero window)
├── EnableStartup.bat         # 1-click installer: auto-starts watcher on Windows boot
├── DisableStartup.bat        # 1-click uninstaller: removes watcher from Windows boot
├── StopWatcher.bat           # Stops any running background watcher instances
├── ViewLogs.bat              # Displays recent sync activity logs with timestamps
├── CheckStatus.bat           # Status checker (shows upload count, recent uploads, retries)
│
├── WatchAndUpload.ps1        # Core PowerShell orchestrator (engine, watcher, SQLite cache)
├── .gitignore                # Protects credentials, tokens, and personal databases
└── README.md                 # Documentation
```

---

## Setup Process (Any New Windows PC)

Setting up on a new device takes under 1 minute:

### 1. Download or Clone the Repository
Clone the repo or download as a ZIP and extract it to any folder of your choice (e.g. `C:\GoogleUnlimited`, `D:\Tools\GoogleUnlimited`, or on a USB drive):
```cmd
git clone https://github.com/shishir0x/GoogleUnlimited.git
```

### 2. Sign In to Google Photos (One-Time)

To spoof Google Pixel unlimited backup, `gotohp` authenticates via Google's Embedded Setup token:

1. Double-click **`gotohp-x64.exe`** and click **Add Google account**.
2. Click **Open Google sign-in** and sign in with the Google account you want to use.
3. Sign in on the Google Embedded Setup page and click **I agree**.  
   *(Note: The page may keep loading / buffering forever; this is completely normal and expected!)*
4. Open your browser Developer Tools (press **F12** or right-click anywhere and choose **Inspect**):
   - Go to the **Application** tab (Chrome / Edge / Brave) or **Storage** tab (Firefox).
   - Under the **Cookies** section in the left panel, click **`https://accounts.google.com`**.
   - Find the cookie named **`oauth_token`** and copy only its value.
5. Return to **`gotohp`**, paste the token value into the input field, and click **Connect account**.
6. Once connected, your auth is securely saved locally. You can now close the GUI window.

### 3. Start Syncing
Choose how you want to run it:
- **Interactive Mode**: Double-click **`RunWatcher.bat`**  
  Opens a terminal showing real-time folder scans, detected files, and live animated upload progress bars.
- **Silent Background Mode**: Double-click **`StartPhotosWatcher.vbs`**  
  Launches invisibly in the background.

---

## How to Use

### 1. Interactive Watcher (`RunWatcher.bat`)
When you run `RunWatcher.bat`, it executes in two automated phases:
- **Phase 1 (Startup Scan)**: Scans all monitored folders for existing unrecorded media and syncs them.
- **Phase 2 (Real-Time Watcher)**: Listens for newly saved, downloaded, or modified photos and videos and uploads them instantly with a live animated progress bar:
  ```text
  [20:10:31] Detected  : holiday_sunset.jpg (1.4 MB)
               Path      : C:\Users\User\Downloads\holiday_sunset.jpg
    [####################] 100% [OK] Uploaded in 4.2s: holiday_sunset.jpg (1.4 MB)
  [2026-10-15 20:10:35][OK] SUCCESS | holiday_sunset.jpg (1.4 MB in 4.2s)
  ```

### 2. Silent Background Mode (`StartPhotosWatcher.vbs`)
To have backups run silently with zero terminal window:
- Double-click **`StartPhotosWatcher.vbs`**.

#### Start Automatically When Windows Turns On (Recommended)
You have two simple ways to enable auto-start on boot:

- **Option A (1-Click Method)**:
  Double-click **`EnableStartup.bat`**.  
  *(To disable auto-start later, simply double-click **`DisableStartup.bat`**).*

- **Option B (Manual Method)**:
  1. Press `Win + R` on your keyboard, type **`shell:startup`**, and hit **Enter**.
  2. Right-click inside the Startup folder → **New** → **Shortcut**.
  3. Browse and select **`StartPhotosWatcher.vbs`** (or drag `StartPhotosWatcher.vbs` into the folder while holding `Alt`).
  4. Click **Next** and **Finish**.

Now, whenever you log into Windows, the sync watcher will run quietly in the background.

#### Stop the Background Watcher (`StopWatcher.bat`)
To stop the background sync at any time, simply double-click **`StopWatcher.bat`**.

### 3. Check Backup Status (`CheckStatus.bat`)
Double-click **`CheckStatus.bat`** anytime to view your sync health without interrupting active background sync:
```text
==========================================================
  *  Google Photos Sync Status
  Database: C:\GoogleUnlimited\gphotos.db
==========================================================
  Total Uploaded Files : 133
  Pending Retries      : 0

  Last 10 Uploads:
    [2026-10-15 20:10:36] pexels-ainc-t-76908403-37156188.jpg
    [2026-10-15 20:10:15] pexels-merve-aktas-yalman-2160736635-38224815.jpg
    [2026-10-15 20:07:34] pexels-roselene-de-koning-791440941-31630142.jpg
==========================================================
```

### 4. View Activity Logs (`ViewLogs.bat`)
Double-click **`ViewLogs.bat`** to view the last 30 timestamped activity events (successes, retries, scan results) recorded in SQLite:
```text
==========================================================
  *  Google Photos Sync - Activity Logs (Last 30)
  Database: C:\GoogleUnlimited\gphotos.db
==========================================================
[2026-10-15 20:10:36][OK] SUCCESS | photo.jpg (1.4 MB in 5.9s)
[2026-10-15 20:17:18][INFO] Cache loaded: 133 uploaded files.
[2026-10-15 20:35:01][OK] SUCCESS | Screenshot.png (10.4 KB in 4.9s)
==========================================================
```

---

## Monitored Folders (Dynamic Resolution)

The watcher automatically detects standard user folders on whatever drive or path they exist on:
- `Downloads`
- `Pictures`
- `Desktop`
- `Documents`
- `Music`

> **Note**: Even if your folders are relocated (e.g. `D:\Downloads`), stored on secondary drives, or redirected by **OneDrive** (`C:\Users\...\OneDrive\Pictures`), the script queries the Windows Shell API and registry to find the real paths automatically.

### Supported File Extensions
- **Images**: `.jpg`, `.jpeg`, `.png`, `.heic`, `.webp`, `.gif`, `.dng`
- **Videos**: `.mp4`, `.mov`, `.mkv`, `.avi`

---

## Privacy & Security

- **Direct Connections Only**: Every API request and media upload connects directly from your PC to official Google Photos endpoints (`photoslibrary.googleapis.com` / Google Media Upload endpoints). No third-party servers or intermediaries exist.
- **Local Credentials**: Authentication tokens are stored locally on your machine in `%APPDATA%\gotohp\` or inside your local directory.
- **Git Protection**: The `.gitignore` file strictly excludes:
  - Database files (`gphotos.db`, `*.db`, `*.db-wal`, `*.db-shm`)
  - Personal config files and tokens (`gotohp.config`, `*.config`, `*.token`)
  - Log files and temporary cache
  Your personal file history and login tokens are **never** committed or pushed to Git.
- **Zero Telemetry**: No tracking, metrics, analytics, or external calls are made.

---

## License & Credits

- Core Pixel upload engine powered by [`xob0t/gotohp`](https://github.com/xob0t/gotohp).
- SQLite integration powered by `PSSQLite`.
