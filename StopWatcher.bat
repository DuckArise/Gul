@echo off
title Stop Google Photos Watcher
echo Stopping Google Photos background watcher...
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*WatchAndUpload.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host ('[OK] Stopped watcher (PID ' + $_.ProcessId + ')') }"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*WatchAndUpload.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host ('[OK] Stopped watcher (PID ' + $_.ProcessId + ')') }"
)
echo.
echo All background watcher instances have been stopped.
timeout /t 3
