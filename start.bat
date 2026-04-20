@echo off
cd /d "%~dp0"
chcp 65001 >nul
title AI CLI Universal Startup Tool

rem Prefer PowerShell 7 pwsh. Check known install paths when PATH lookup fails.
set "PWSH_EXE="
where pwsh >nul 2>&1 && set "PWSH_EXE=pwsh.exe"
if not defined PWSH_EXE if exist "C:\Program Files\PowerShell\7\pwsh.exe" set "PWSH_EXE=C:\Program Files\PowerShell\7\pwsh.exe"
if not defined PWSH_EXE if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH_EXE if exist "%LOCALAPPDATA%\Microsoft\PowerShell\7\pwsh.exe" set "PWSH_EXE=%LOCALAPPDATA%\Microsoft\PowerShell\7\pwsh.exe"

if defined PWSH_EXE goto :RUN_PWSH
echo [WARN] PowerShell 7 pwsh not found. Using Windows PowerShell 5.1 fallback.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\main\Start-Menu.ps1"
goto :EOF

:RUN_PWSH
"%PWSH_EXE%" -NoProfile -ExecutionPolicy Bypass -File "scripts\main\Start-Menu.ps1"
