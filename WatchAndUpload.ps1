# =====================================================================
#  Google Photos Auto-Sync & Real-Time Watcher - Portable Edition
#  Runs on ANY Windows PC, in ANY folder, on PS 5.1 and PS 7+
#  Zero hardcoded paths - Self-contained SQLite engine
# =====================================================================
param(
    [switch]$StatusOnly,
    [switch]$ShowLogs
)
$ErrorActionPreference = "Stop"

# -- Dynamic Base Directory (Wherever this script is located) ----------
$script:BASE = $PSScriptRoot
if (-not $script:BASE) {
    $script:BASE = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $script:BASE) {
    $script:BASE = (Get-Location).Path
}

# -- Executable & Database Discovery -----------------------------------
$script:GOTOHP = $null
$binCandidates = @(
    "gotohp-cli-x64.exe",
    "gotohp-cli.exe",
    "gotohp-x64.exe",
    "gotohp.exe"
)

foreach ($cand in $binCandidates) {
    $testPath = Join-Path $script:BASE $cand
    if ([System.IO.File]::Exists($testPath)) {
        $script:GOTOHP = $testPath
        break
    }
}

if (-not $script:GOTOHP) {
    foreach ($cand in $binCandidates) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($cand)
        $pathCmd = Get-Command $baseName -ErrorAction SilentlyContinue
        if ($pathCmd) {
            $script:GOTOHP = $pathCmd.Source
            break
        }
    }
}

$script:DB = Join-Path $script:BASE "gphotos.db"

# -- Portable Config Discovery (Checks local folder first, then %APPDATA%)
$script:CONFIG_ARGS = @()
$portableConfig = Join-Path $script:BASE "gotohp.config"
if ([System.IO.File]::Exists($portableConfig)) {
    $script:CONFIG_ARGS = @("--config", $portableConfig)
}

# -- Dynamic Windows Shell Folders (Resolves OneDrive/Custom Drives) ---
$userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)

function Resolve-ExistingFolder([string]$fPath) {
    if (-not [string]::IsNullOrWhiteSpace($fPath)) {
        $expanded = [Environment]::ExpandEnvironmentVariables($fPath)
        if ([System.IO.Directory]::Exists($expanded)) {
            return (Resolve-Path -LiteralPath $expanded).Path
        }
    }
    return $null
}

# Read Downloads path from Windows registry (covers relocated/OneDrive downloads)
$regDownloads = $null
try {
    $regVal = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue)."{374DE290-123F-4565-9164-39C4925E467B}"
    if ($regVal) { $regDownloads = $regVal }
} catch {}

$folderCandidates = @(
    $regDownloads,
    [Environment]::GetFolderPath([Environment+SpecialFolder]::MyPictures),
    [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop),
    [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments),
    [Environment]::GetFolderPath([Environment+SpecialFolder]::MyMusic),
    (Join-Path $userHome "Downloads"),
    (Join-Path $userHome "Pictures"),
    (Join-Path $userHome "Desktop"),
    (Join-Path $userHome "Documents"),
    (Join-Path $userHome "Music")
)

$seenFolders = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$script:WATCH_DIRS = New-Object 'System.Collections.Generic.List[string]'

foreach ($cand in $folderCandidates) {
    $resolved = Resolve-ExistingFolder $cand
    if ($resolved -and -not $seenFolders.Contains($resolved)) {
        $seenFolders.Add($resolved) | Out-Null
        $script:WATCH_DIRS.Add($resolved) | Out-Null
    }
}

# -- Supported extensions ----------------------------------------------
$script:EXT = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$extList = @(".jpg", ".jpeg", ".png", ".heic", ".webp", ".gif",
             ".mp4", ".mov", ".mkv", ".avi", ".dng")
foreach ($e in $extList) { $script:EXT.Add($e) | Out-Null }

$script:MIN_BYTES = 10240   # 10 KB minimum file size
$script:MAX_RETRY = 3       # Max retry attempts per file
$script:LOG_RETENTION_DAYS = 30

# In-memory cache for O(1) lookups
$script:history  = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$script:retryMap = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::OrdinalIgnoreCase)
$script:inFlight = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

# Mutex for thread-safe DB access
$script:dbMutex = New-Object System.Threading.Mutex($false, "GotohpDBMutex")

# ---------------------------------------------------------------------
# PORTABLE PSSQLITE ENGINE LOADER (Zero configuration required)
# ---------------------------------------------------------------------
if (-not (Get-Module -Name PSSQLite)) {
    $modulePaths = @(
        # 1. Bundled inside script's own directory (Fully portable on USB/any PC)
        (Join-Path $script:BASE "Modules\PSSQLite\PSSQLite.psd1"),
        (Join-Path $script:BASE "Modules\PSSQLite\1.1.0\PSSQLite.psd1"),
        # 2. Installed in user profile
        (Join-Path $env:USERPROFILE "Documents\PowerShell\Modules\PSSQLite\1.1.0\PSSQLite.psd1"),
        (Join-Path $env:USERPROFILE "Documents\PowerShell\Modules\PSSQLite\PSSQLite.psd1"),
        (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Modules\PSSQLite\1.1.0\PSSQLite.psd1"),
        (Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Modules\PSSQLite\PSSQLite.psd1")
    )

    $loaded = $false
    foreach ($mp in $modulePaths) {
        if ([System.IO.File]::Exists($mp)) {
            Import-Module -Name $mp -ErrorAction SilentlyContinue
            $loaded = $true
            break
        }
    }

    if (-not $loaded) {
        # Check standard module discovery
        Import-Module -Name PSSQLite -ErrorAction SilentlyContinue
    }
}

# Auto-install fallback if running on a fresh PC without bundled modules
if (-not (Get-Command -Name Invoke-SqliteQuery -ErrorAction SilentlyContinue)) {
    Write-Host "[Setup] SQLite module not detected. Installing automatically..." -ForegroundColor Yellow
    try {
        Install-Module -Name PSSQLite -Force -Scope CurrentUser -ErrorAction Stop
        Import-Module PSSQLite -ErrorAction Stop
        Write-Host "[Setup] SQLite module installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Could not load or install PSSQLite. Please check internet connection." -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------------
# DB INIT
# ---------------------------------------------------------------------
function Initialize-DB {
    $ddl = @"
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
"@
    Invoke-SqliteQuery -DataSource $script:DB -Query $ddl | Out-Null
}

# ---------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------
function Write-Log([string]$msg, [string]$level = "INFO") {
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$level] $msg"
    try {
        $null = $script:dbMutex.WaitOne(3000)
        Invoke-SqliteQuery -DataSource $script:DB `
            -Query "INSERT INTO logs(level, message) VALUES(@lv, @m)" `
            -SqlParameters @{ lv = $level; m = $msg } | Out-Null
    } catch {}
    finally {
        try { $script:dbMutex.ReleaseMutex() } catch {}
    }

    switch ($level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor DarkYellow }
        "OK"    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line -ForegroundColor Gray }
    }
}

# ---------------------------------------------------------------------
# CACHE & PRUNE
# ---------------------------------------------------------------------
function Load-Cache {
    $rows = Invoke-SqliteQuery -DataSource $script:DB -Query "SELECT path FROM uploads"
    foreach ($r in $rows) {
        if ($r.path) {
            $script:history.Add($r.path) | Out-Null
        }
    }
    Write-Log "Cache loaded: $($script:history.Count) uploaded files."

    $retries = Invoke-SqliteQuery -DataSource $script:DB -Query "SELECT path, attempts FROM retry_queue"
    foreach ($r in $retries) {
        if ($r.path -and -not $script:history.Contains($r.path)) {
            $script:retryMap[$r.path] = [int]$r.attempts
        }
    }
    if ($script:retryMap.Count -gt 0) {
        Write-Log "Retry queue: $($script:retryMap.Count) file(s) pending." "WARN"
    }

    Invoke-SqliteQuery -DataSource $script:DB `
        -Query "DELETE FROM logs WHERE timestamp < datetime('now', '-$($script:LOG_RETENTION_DAYS) days')" | Out-Null
}

function Save-Upload([string]$path, [string]$mediaKey) {
    try {
        $null = $script:dbMutex.WaitOne(3000)
        Invoke-SqliteQuery -DataSource $script:DB `
            -Query "INSERT OR REPLACE INTO uploads(path, media_key) VALUES(@p, @k)" `
            -SqlParameters @{ p = $path; k = $mediaKey } | Out-Null
        Invoke-SqliteQuery -DataSource $script:DB `
            -Query "DELETE FROM retry_queue WHERE path = @p" `
            -SqlParameters @{ p = $path } | Out-Null
        $script:history.Add($path)     | Out-Null
        $null = $script:retryMap.Remove($path)
    } finally {
        try { $script:dbMutex.ReleaseMutex() } catch {}
    }
}

function Save-Retry([string]$path, [int]$attempts) {
    try {
        $null = $script:dbMutex.WaitOne(3000)
        Invoke-SqliteQuery -DataSource $script:DB `
            -Query "INSERT OR REPLACE INTO retry_queue(path, attempts, last_attempt) VALUES(@p, @a, datetime('now','localtime'))" `
            -SqlParameters @{ p = $path; a = $attempts } | Out-Null
        $script:retryMap[$path] = $attempts
    } finally {
        try { $script:dbMutex.ReleaseMutex() } catch {}
    }
}

function Remove-Retry([string]$path) {
    try {
        $null = $script:dbMutex.WaitOne(3000)
        Invoke-SqliteQuery -DataSource $script:DB `
            -Query "DELETE FROM retry_queue WHERE path = @p" `
            -SqlParameters @{ p = $path } | Out-Null
        $null = $script:retryMap.Remove($path)
    } finally {
        try { $script:dbMutex.ReleaseMutex() } catch {}
    }
}

# ---------------------------------------------------------------------
# FILE READINESS CHECK
# ---------------------------------------------------------------------
function Wait-ForFileReady([string]$path) {
    for ($i = 0; $i -lt 30; $i++) {
        try {
            if (-not [System.IO.File]::Exists($path)) { return $false }
            $info = New-Object System.IO.FileInfo($path)
            if ($info.Length -lt $script:MIN_BYTES) {
                Start-Sleep -Seconds 1
                continue
            }
            $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'None')
            $fs.Close()
            $fs.Dispose()
            return $true
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

# ---------------------------------------------------------------------
# CORE UPLOAD FUNCTION WITH DYNAMIC IN-PLACE PROGRESS BAR
# ---------------------------------------------------------------------
function Invoke-Upload([string]$path, [int]$current = 1, [int]$total = 1) {
    if ($path.Contains("\Modules\")) { return }
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    if (-not $script:EXT.Contains($ext)) { return }
    if ($script:history.Contains($path)) { return }
    if (-not $script:inFlight.Add($path)) { return }

    try {
        $name = [System.IO.Path]::GetFileName($path)
        $fileInfo = New-Object System.IO.FileInfo($path)
        $fileSizeMB = [Math]::Round($fileInfo.Length / 1MB, 2)
        if ($fileSizeMB -lt 1) {
            $sizeLabel = "$([Math]::Round($fileInfo.Length / 1KB, 1)) KB"
        } else {
            $sizeLabel = "$fileSizeMB MB"
        }

        Write-Host ""
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Detected  : $name ($sizeLabel)" -ForegroundColor Cyan
        Write-Host "             Path      : $path"                               -ForegroundColor DarkGray

        if (-not (Wait-ForFileReady $path)) {
            Write-Log "File not ready or too small: $name" "WARN"
            $prev = 0
            if ($script:retryMap.ContainsKey($path)) { $prev = $script:retryMap[$path] }
            Save-Retry $path ($prev + 1)
            return
        }

        # Start gotohp-cli and render live active progress bar with elapsed time
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:GOTOHP
        $uploadArgs = @()
        if ($script:CONFIG_ARGS.Count -gt 0) {
            $uploadArgs += $script:CONFIG_ARGS
        }
        $uploadArgs += @("upload", "`"$path`"")
        $psi.Arguments = $uploadArgs -join " "
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $barWidth = 20
        $step = 0

        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 150
            $elapsedSec = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
            $step = ($step + 1) % $barWidth

            $barChars = [char[]]("-" * $barWidth)
            for ($k = 0; $k -lt 4; $k++) {
                $barChars[($step + $k) % $barWidth] = [char]"#"
            }
            $activeBar = -join $barChars
            [Console]::Write("`r  [$activeBar] Uploading $sizeLabel ($($elapsedSec)s)...   ")
        }

        $proc.WaitForExit()
        $exitCode = $proc.ExitCode
        $totalTime = [Math]::Round($sw.Elapsed.TotalSeconds, 1)
        $doneBar = "#" * $barWidth

        if ($exitCode -eq 0) {
            [Console]::Write("`r  [$doneBar] 100% [OK] Uploaded in $($totalTime)s: $name ($sizeLabel)        `n")
            Write-Log "SUCCESS | $name ($sizeLabel in $($totalTime)s)" "OK"
            Save-Upload $path ""
        } else {
            [Console]::Write("`r  [--------------------] FAILED in $($totalTime)s: $name                      `n")
            $attempts = 1
            if ($script:retryMap.ContainsKey($path)) {
                $attempts = $script:retryMap[$path] + 1
            }

            if ($attempts -ge $script:MAX_RETRY) {
                Write-Log "GAVE UP after $attempts attempts: $name" "ERROR"
                Remove-Retry $path
            } else {
                Write-Log "FAILED (attempt $attempts/$($script:MAX_RETRY)) - queued for retry: $name" "WARN"
                Save-Retry $path $attempts
            }
        }
    } catch {
        Write-Log "EXCEPTION for $([System.IO.Path]::GetFileName($path)): $_" "ERROR"
    } finally {
        $null = $script:inFlight.Remove($path)
    }
}

# ---------------------------------------------------------------------
# STARTUP BANNER
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  *  Google Photos Auto-Sync - gotohp (Portable Edition)"   -ForegroundColor Green
Write-Host "  Location: $script:BASE"                                   -ForegroundColor Yellow
Write-Host "  Database: $script:DB"                                     -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Watched Folders:" -ForegroundColor DarkCyan
foreach ($dir in $script:WATCH_DIRS) {
    Write-Host "    -> $dir" -ForegroundColor Gray
}
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

if (-not [System.IO.File]::Exists($script:GOTOHP)) {
    Write-Host "ERROR: gotohp binary not found in $script:BASE or system PATH." -ForegroundColor Red
    exit 1
}

# Check for active Google Photos account
$checkArgs = @()
if ($script:CONFIG_ARGS.Count -gt 0) {
    $checkArgs += $script:CONFIG_ARGS
}
$checkArgs += @("creds", "list")

$credsOutput = & $script:GOTOHP $checkArgs 2>&1 | Out-String
if ($credsOutput -match "No credentials found" -or ($credsOutput -notmatch "\*")) {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host "  ACTION REQUIRED: No Google Account Logged In!"            -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host "  Please sign in to Google Photos first:"                  -ForegroundColor White
    Write-Host "    1. Double-click 'gotohp-x64.exe' to log in via GUI, OR" -ForegroundColor Gray
    Write-Host "    2. Run: .\gotohp-cli-x64.exe creds add"                 -ForegroundColor Gray
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host ""
    if (-not $StatusOnly) {
        exit 1
    }
}

Initialize-DB
Load-Cache

if ($StatusOnly) {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "  *  Google Photos Sync Status"                             -ForegroundColor Green
    Write-Host "  Database: $script:DB"                                     -ForegroundColor Gray
    Write-Host "==========================================================" -ForegroundColor Cyan
    
    $totalCount = $script:history.Count
    $retCount   = $script:retryMap.Count
    Write-Host "  Total Uploaded Files : $totalCount" -ForegroundColor Yellow
    Write-Host "  Pending Retries      : $retCount"   -ForegroundColor $(if ($retCount -gt 0) { "Red" } else { "Green" })
    
    $recent = Invoke-SqliteQuery -DataSource $script:DB `
        -Query "SELECT path, uploaded_at FROM uploads ORDER BY uploaded_at DESC LIMIT 10"
    if ($recent) {
        Write-Host ""
        Write-Host "  Last 10 Uploads:" -ForegroundColor Cyan
        foreach ($r in $recent) {
            $name = [System.IO.Path]::GetFileName($r.path)
            Write-Host "    [$($r.uploaded_at)] $name" -ForegroundColor Gray
        }
    }
    
    if ($retCount -gt 0) {
        Write-Host ""
        Write-Host "  Pending Retries in Queue:" -ForegroundColor DarkYellow
        foreach ($qf in $script:retryMap.Keys) {
            Write-Host "    $qf (attempt $($script:retryMap[$qf]))" -ForegroundColor DarkYellow
        }
    }
    Write-Host "==========================================================" -ForegroundColor Cyan
    return
}

if ($ShowLogs) {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "  *  Google Photos Sync - Activity Logs (Last 30)"          -ForegroundColor Green
    Write-Host "  Database: $script:DB"                                     -ForegroundColor Gray
    Write-Host "==========================================================" -ForegroundColor Cyan

    $logRows = Invoke-SqliteQuery -DataSource $script:DB `
        -Query "SELECT timestamp, level, message FROM logs ORDER BY id DESC LIMIT 30"
    if ($logRows) {
        $logArray = @($logRows)
        [Array]::Reverse($logArray)
        foreach ($l in $logArray) {
            $color = switch ($l.level) {
                "ERROR" { "Red" }
                "WARN"  { "DarkYellow" }
                "OK"    { "Green" }
                default { "Gray" }
            }
            Write-Host "[$($l.timestamp)][$($l.level)] $($l.message)" -ForegroundColor $color
        }
    } else {
        Write-Host "  No activity logs found." -ForegroundColor DarkGray
    }
    Write-Host "==========================================================" -ForegroundColor Cyan
    return
}

# ---------------------------------------------------------------------
# PHASE 1 - Startup scan for unrecorded files
# ---------------------------------------------------------------------
Write-Host "[Phase 1] Scanning for unrecorded files..." -ForegroundColor Cyan

$unrecorded = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'

foreach ($dir in $script:WATCH_DIRS) {
    try {
        Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $script:EXT.Contains($_.Extension.ToLower()) -and
                -not $_.FullName.Contains("\Modules\") -and
                -not $script:history.Contains($_.FullName)
            } | ForEach-Object { $unrecorded.Add($_) }
    } catch {
        Write-Log "Scan error in $dir - $_" "WARN"
    }
}

# Include pending retry queue files
foreach ($qf in @($script:retryMap.Keys)) {
    $fi = New-Object System.IO.FileInfo($qf)
    if ($fi.Exists -and -not $script:history.Contains($qf)) {
        $unrecorded.Add($fi)
    }
}

if ($unrecorded.Count -eq 0) {
    Write-Host "[Phase 1] [OK] Everything backed up - zero new files." -ForegroundColor Green
} else {
    $total = $unrecorded.Count
    Write-Host "[Phase 1] Found $total file(s) to upload." -ForegroundColor Yellow
    $i = 0
    foreach ($f in $unrecorded) {
        $i++
        $pct = [Math]::Round(($i / $total) * 100)
        Write-Progress -Activity "Startup sync" -Status "[$i/$total] $($f.Name)" -PercentComplete $pct
        Invoke-Upload $f.FullName $i $total
    }
    Write-Progress -Activity "Startup sync" -Completed
    Write-Host "[Phase 1] [OK] Startup sync complete ($total file(s))." -ForegroundColor Green
}

# ---------------------------------------------------------------------
# PHASE 2 - Real-time watchers
# ---------------------------------------------------------------------
Write-Host ""
Write-Host "[Phase 2] Real-time watcher active." -ForegroundColor Yellow
Write-Host "  Waiting for new downloads... Press Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

$action = { Invoke-Upload $Event.SourceEventArgs.FullPath 1 1 }

$script:watchers = New-Object 'System.Collections.Generic.List[System.IO.FileSystemWatcher]'

foreach ($dir in $script:WATCH_DIRS) {
    try {
        $w = New-Object System.IO.FileSystemWatcher
        $w.Path                  = $dir
        $w.IncludeSubdirectories = $true
        $w.InternalBufferSize    = 65536
        $w.NotifyFilter          = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite

        Register-ObjectEvent $w 'Error' -Action {
            Write-Log "FSW buffer overflow on $($Event.Sender.Path)" "WARN"
        } | Out-Null
        Register-ObjectEvent $w 'Created' -Action $action | Out-Null
        Register-ObjectEvent $w 'Renamed' -Action $action | Out-Null

        $w.EnableRaisingEvents = $true
        $script:watchers.Add($w)
    } catch {
        Write-Log "Could not watch $dir - $_" "WARN"
    }
}

# ---------------------------------------------------------------------
# MAIN LOOP - safety sweep + retry flush every 30 s
# ---------------------------------------------------------------------
try {
    $lastSweep = [DateTime]::MinValue
    while ($true) {
        Start-Sleep -Seconds 2

        if (([DateTime]::Now - $lastSweep).TotalSeconds -ge 30) {
            $lastSweep = [DateTime]::Now

            # Safety sweep
            foreach ($dir in $script:WATCH_DIRS) {
                try {
                    Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue |
                        Where-Object {
                            $script:EXT.Contains($_.Extension.ToLower()) -and
                            -not $_.FullName.Contains("\Modules\") -and
                            -not $script:history.Contains($_.FullName) -and
                            -not $script:inFlight.Contains($_.FullName) -and
                            $_.LastWriteTime -gt ([DateTime]::Now.AddMinutes(-10))
                        } | ForEach-Object {
                            Write-Log "Sweep caught missed file: $($_.Name)" "WARN"
                            Invoke-Upload $_.FullName 1 1
                        }
                } catch {
                    Write-Log "Sweep error in $dir - $_" "WARN"
                }
            }

            # Retry queue flush
            foreach ($qf in @($script:retryMap.Keys)) {
                if ($script:history.Contains($qf)) {
                    Remove-Retry $qf
                    continue
                }
                if ([System.IO.File]::Exists($qf)) {
                    Write-Log "Retrying: $([System.IO.Path]::GetFileName($qf)) (attempt $($script:retryMap[$qf]+1))" "WARN"
                    Invoke-Upload $qf 1 1
                }
            }
        }
    }
} finally {
    foreach ($w in $script:watchers) {
        try {
            $w.EnableRaisingEvents = $false
            $w.Dispose()
        } catch {}
    }
    Get-EventSubscriber -ErrorAction SilentlyContinue |
        Where-Object { $_.SourceIdentifier -notlike "PowerShell*" } |
        Unregister-Event -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "Watcher stopped. Database: $script:DB" -ForegroundColor Red
    Write-Log "Watcher stopped cleanly." "INFO"
}
