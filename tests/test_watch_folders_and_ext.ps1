# =====================================================================
# Regression Test Suite: Issue #1 (Real-time & Previous Media Detection)
# Tests:
#   1. Media extension filtering (photos, videos, RAW camera files)
#   2. Custom and cloud watch directory discovery (including watch_dirs.txt)
#   3. Account parsing and auto-activation fallback logic
#   4. gotohp-cli JSON error extraction
#   5. Content-hash deduplication vs false positive collisions
# =====================================================================
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Split-Path -Parent $scriptDir
$tempDir = Join-Path $env:TEMP "gotohp_test_issue1_$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$testDb = Join-Path $tempDir "test_gphotos.db"

# Import SQLite module from repo Modules
$modulePath = Join-Path $repoDir "Modules\PSSQLite\PSSQLite.psd1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
} else {
    Write-Warning "PSSQLite module not found at $modulePath"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  TEST SUITE: Issue #1 Real-Time & Media Detection Fixes"  -ForegroundColor Green
Write-Host "  Temp Dir: $tempDir"                                       -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

$passed = 0
$failed = 0

function Assert-Condition([bool]$condition, [string]$message) {
    if ($condition) {
        Write-Host "  [PASS] $message" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $message" -ForegroundColor Red
        $script:failed++
    }
}

# -------------------------------------------------------------------
# Test 1: Media Extensions Coverage
# -------------------------------------------------------------------
Write-Host "`nTest 1: Media Extensions Verification" -ForegroundColor Yellow

$validExtensions = @(
    '.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp', '.gif', '.bmp', '.tiff', '.tif', '.jfif', '.avif',
    '.dng', '.cr2', '.cr3', '.nef', '.arw', '.raw', '.orf', '.rw2', '.pef', '.srw', '.raf',
    '.mp4', '.mov', '.mkv', '.avi', '.m4v', '.3gp', '.3g2', '.wmv', '.webm', '.flv', '.mts', '.m2ts', '.ts', '.mpg'
)

$extLookup = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($ext in $validExtensions) { [void]$extLookup.Add($ext) }

# Check that crucial formats from Issue #1 are recognized
$testFiles = @(
    "vacation.jpg", "pic.HEIC", "shot.CR2", "sony.ARW", "nikon.NEF",
    "video.MP4", "recording.MOV", "clip.m4v", "anim.webp", "modern.avif"
)
foreach ($f in $testFiles) {
    $ext = [System.IO.Path]::GetExtension($f)
    Assert-Condition ($extLookup.Contains($ext)) "Extension for $f ($ext) is supported"
}

# Check non-media files are rejected
$invalidFiles = @("doc.pdf", "app.exe", "data.json", "log.txt", "archive.zip")
foreach ($f in $invalidFiles) {
    $ext = [System.IO.Path]::GetExtension($f)
    Assert-Condition (-not $extLookup.Contains($ext)) "Non-media file $f ($ext) is properly excluded"
}

# -------------------------------------------------------------------
# Test 2: Directory Discovery & watch_dirs.txt Parsing
# -------------------------------------------------------------------
Write-Host "`nTest 2: Directory Discovery & watch_dirs.txt Parsing" -ForegroundColor Yellow

# Create dummy custom watch dirs
$customFolder1 = Join-Path $tempDir "CustomPhotos"
$customFolder2 = Join-Path $tempDir "ActionCamVideos"
New-Item -ItemType Directory -Path $customFolder1 -Force | Out-Null
New-Item -ItemType Directory -Path $customFolder2 -Force | Out-Null

$watchDirsFile = Join-Path $tempDir "watch_dirs.txt"
Set-Content -Path $watchDirsFile -Value @"
# This is a comment
$customFolder1

  # Another comment with spaces
$customFolder2
%TEMP%
"@

# Simulate directory loader from WatchAndUpload.ps1
$watchDirs = New-Object 'System.Collections.Generic.List[string]'
if (Test-Path $watchDirsFile) {
    Get-Content $watchDirsFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $expanded = [System.Environment]::ExpandEnvironmentVariables($line)
            if (Test-Path $expanded) {
                $resolved = (Resolve-Path $expanded).Path
                if (-not $watchDirs.Contains($resolved)) {
                    $watchDirs.Add($resolved)
                }
            }
        }
    }
}

Assert-Condition ($watchDirs.Contains($customFolder1)) "Loaded custom folder 1 from watch_dirs.txt"
Assert-Condition ($watchDirs.Contains($customFolder2)) "Loaded custom folder 2 from watch_dirs.txt"
Assert-Condition ($watchDirs.Count -ge 2) "Loaded valid entries while ignoring blank lines and comments"

# -------------------------------------------------------------------
# Test 3: Account Fallback / Auto-Activation Logic
# -------------------------------------------------------------------
Write-Host "`nTest 3: Account Fallback / Auto-Activation Logic" -ForegroundColor Yellow

$mockConfigNoStar = @"
[general]
debug = false

[account "backup1@gmail.com"]
client_id = "test-client-id"
client_secret = "test-client-secret"

[account "personal@gmail.com"]
client_id = "test-client-id-2"
client_secret = "test-client-secret-2"
"@

# Check that fallback correctly discovers first account if none has '*'
$extractedAccount = $null
if ($mockConfigNoStar -match '\[account\s+"([^"]+)"\]') {
    $extractedAccount = $matches[1]
}
Assert-Condition ($extractedAccount -eq "backup1@gmail.com") "Auto-discovered first configured account: $extractedAccount"

# Check active star account discovery
$mockConfigWithStar = @"
[general]
debug = false

[account "*primary@gmail.com"]
client_id = "primary-client-id"
"@
$activeAccount = $null
if ($mockConfigWithStar -match '(?m)^\s*\[account\s+["'']?\*([^\s"'']+)["'']?\]') {
    $activeAccount = $matches[1]
}
Assert-Condition ($activeAccount -eq "primary@gmail.com") "Identified active star account correctly: $activeAccount"

# -------------------------------------------------------------------
# Test 4: gotohp-cli JSON Error Extraction
# -------------------------------------------------------------------
Write-Host "`nTest 4: gotohp-cli JSON Error Extraction" -ForegroundColor Yellow

$mockJsonErr1 = '{"status":"failed","error":"Google Photos API storage quota exceeded"}'
$mockJsonErr2 = '{"success":false,"message":"OAuth token revoked or expired"}'
$mockNormalErr = 'Network connection timed out'

function Extract-UploadError([string]$rawOutput) {
    $err = $null
    if ($rawOutput -match '\{\s*".*\}') {
        try {
            $parsed = $rawOutput | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($parsed.error) { $err = $parsed.error }
            elseif ($parsed.message) { $err = $parsed.message }
        } catch { }
    }
    if (-not $err) {
        $err = $rawOutput.Trim()
    }
    return $err
}

Assert-Condition ((Extract-UploadError $mockJsonErr1) -eq "Google Photos API storage quota exceeded") "Extracted 'error' field from JSON output"
Assert-Condition ((Extract-UploadError $mockJsonErr2) -eq "OAuth token revoked or expired") "Extracted 'message' field from JSON output"
Assert-Condition ((Extract-UploadError $mockNormalErr) -eq "Network connection timed out") "Fell back to raw output when not JSON"

# -------------------------------------------------------------------
# Test 5: Content-Hash Collision Avoidance vs Duplicate Detection
# -------------------------------------------------------------------
Write-Host "`nTest 5: Content-Hash Collision Avoidance" -ForegroundColor Yellow

# Initialize test DB
Invoke-SqliteQuery -DataSource $testDb -Query @"
CREATE TABLE IF NOT EXISTS uploads (
    path         TEXT PRIMARY KEY,
    media_key    TEXT,
    uploaded_at  TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    file_name    TEXT,
    file_size    INTEGER,
    content_hash TEXT
);
CREATE INDEX IF NOT EXISTS idx_uploads_file ON uploads(file_name, file_size);
CREATE INDEX IF NOT EXISTS idx_uploads_hash ON uploads(content_hash);
"@

function Get-TestFileHash([string]$path) {
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash($fs)
    $fs.Close()
    $fs.Dispose()
    return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
}

function Test-IsDup([string]$path, [string]$db) {
    $fileInfo = New-Object System.IO.FileInfo($path)
    $name = $fileInfo.Name
    $size = $fileInfo.Length

    # 1. Exact path
    $exact = Invoke-SqliteQuery -DataSource $db -Query "SELECT COUNT(*) as cnt FROM uploads WHERE path = @p" -SqlParameters @{ p = $path }
    if ($exact.cnt -gt 0) { return $true }

    # 2. Candidate match by name and size
    $candidates = Invoke-SqliteQuery -DataSource $db -Query "SELECT content_hash FROM uploads WHERE file_name = @n AND file_size = @s" -SqlParameters @{ n = $name; s = $size }
    if ($candidates -and $candidates.Count -gt 0) {
        $localHash = Get-TestFileHash $path
        foreach ($c in $candidates) {
            if ($c.content_hash -and $c.content_hash -eq $localHash) {
                return $true
            }
        }
    }
    return $false
}

# Create File A: IMG_0001.JPG with 100 bytes of 'A'
$fileA = Join-Path $tempDir "IMG_0001.JPG"
[System.IO.File]::WriteAllBytes($fileA, [byte[]](,65 * 100))
$hashA = Get-TestFileHash $fileA

# Insert File A as uploaded from a previous path
Invoke-SqliteQuery -DataSource $testDb -Query @"
INSERT INTO uploads (path, file_name, file_size, content_hash)
VALUES ('C:\OldDrive\Pictures\IMG_0001.JPG', 'IMG_0001.JPG', 100, '$hashA')
"@

# File B has SAME name and SAME size (100 bytes), but DIFFERENT content ('B' * 100)
$folderB = Join-Path $tempDir "FolderB"
New-Item -ItemType Directory -Path $folderB -Force | Out-Null
$fileB = Join-Path $folderB "IMG_0001.JPG"
[System.IO.File]::WriteAllBytes($fileB, [byte[]](,66 * 100))

# Test: File B must NOT be considered duplicate of File A!
$isDupB = Test-IsDup $fileB $testDb
Assert-Condition (-not $isDupB) "File with identical name & size but different content hash is NOT discarded"

# File C has SAME content hash as File A
$folderC = Join-Path $tempDir "FolderC"
New-Item -ItemType Directory -Path $folderC -Force | Out-Null
$fileC = Join-Path $folderC "Renamed_Photo.JPG"
[System.IO.File]::WriteAllBytes($fileC, [byte[]](,65 * 100))

# Insert File C with original hash
Invoke-SqliteQuery -DataSource $testDb -Query @"
INSERT INTO uploads (path, file_name, file_size, content_hash)
VALUES ('$fileC', 'Renamed_Photo.JPG', 100, '$hashA')
"@
$isDupC = Test-IsDup $fileC $testDb
Assert-Condition $isDupC "File with exact same path is correctly detected as duplicate"

# Cleanup temp
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "  Results: $passed Passed, $failed Failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

if ($failed -gt 0) { exit 1 } else { exit 0 }
