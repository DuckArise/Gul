@echo off
title Disable Auto-Start on Windows Boot
cd /d "%~dp0"
echo Removing Google Photos Auto-Sync from Windows startup...

where pwsh.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "$path = Join-Path ([Environment]::GetFolderPath('Startup')) 'GoogleUnlimited.lnk'; if (Test-Path $path) { Remove-Item $path -Force; Write-Host '[OK] Startup shortcut removed successfully!' -ForegroundColor Green } else { Write-Host 'Shortcut was not present in Startup folder.' -ForegroundColor Yellow }"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$path = Join-Path ([Environment]::GetFolderPath('Startup')) 'GoogleUnlimited.lnk'; if (Test-Path $path) { Remove-Item $path -Force; Write-Host '[OK] Startup shortcut removed successfully!' -ForegroundColor Green } else { Write-Host 'Shortcut was not present in Startup folder.' -ForegroundColor Yellow }"
)

echo.
echo ========================================================
echo  Auto-Start disabled. The watcher will no longer start
echo  automatically when Windows boots.
echo ========================================================
echo.
timeout /t 4
