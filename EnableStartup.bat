@echo off
title Enable Auto-Start on Windows Boot
cd /d "%~dp0"
echo Setting up Google Photos Auto-Sync to run on Windows startup...

where pwsh.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'GoogleUnlimited.lnk')); $s.TargetPath = (Join-Path '%~dp0' 'StartPhotosWatcher.vbs'); $s.WorkingDirectory = '%~dp0'; $s.Description = 'Google Photos Unlimited Auto-Sync Watcher'; $s.Save(); Write-Host '[OK] Startup shortcut created successfully!' -ForegroundColor Green"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'GoogleUnlimited.lnk')); $s.TargetPath = (Join-Path '%~dp0' 'StartPhotosWatcher.vbs'); $s.WorkingDirectory = '%~dp0'; $s.Description = 'Google Photos Unlimited Auto-Sync Watcher'; $s.Save(); Write-Host '[OK] Startup shortcut created successfully!' -ForegroundColor Green"
)

echo.
echo ========================================================
echo  Google Photos Auto-Sync will now start automatically
echo  in the background every time your computer turns on.
echo ========================================================
echo.
timeout /t 4
