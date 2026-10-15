@echo off
title Google Photos Auto-Sync Watcher
cd /d "%~dp0"
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WatchAndUpload.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WatchAndUpload.ps1"
)
pause
