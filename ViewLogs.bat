@echo off
title Google Photos Sync Activity Logs
cd /d "%~dp0"
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "& { & '%~dp0WatchAndUpload.ps1' -ShowLogs }"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { & '%~dp0WatchAndUpload.ps1' -ShowLogs }"
)
pause
