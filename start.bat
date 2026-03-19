@echo off
cd /d "%~dp0"
title AI CLI Universal Startup Tool
where pwsh >nul 2>&1
if %ERRORLEVEL% == 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\main\Start-Menu.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\main\Start-Menu.ps1"
)
