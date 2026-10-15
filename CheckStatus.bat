@echo off
title Google Photos Backup Status
cd /d "%~dp0"
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "& { & '%~dp0WatchAndUpload.ps1' -StatusOnly }"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { & '%~dp0WatchAndUpload.ps1' -StatusOnly }"
)
pause
