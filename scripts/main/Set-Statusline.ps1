<#
.SYNOPSIS
    メニュー 13 本体。Windows 側 ~/.claude/settings.json の statusLine を Linux 側へ同期する。
.DESCRIPTION
    ClaudeOS v3.1.0 / Statusline グローバル設定を全プロジェクトに一括適用
#>

param(
    [switch]$NonInteractive
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\StatuslineManager.psm1') -Force -DisableNameChecking

$ConfigPath = Get-StartupConfigPath -StartupRoot $ScriptRoot
$Config = Import-LauncherConfig -ConfigPath $ConfigPath
$LinuxHost = $Config.linuxHost

Write-Host ""
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host "   Statusline グローバル設定 適用" -ForegroundColor Cyan
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host ""

$sourcePath = if ($Config.PSObject.Properties.Name -contains 'statusline' -and `
    $Config.statusline.PSObject.Properties.Name -contains 'sourceSettingsPath') {
    [Environment]::ExpandEnvironmentVariables($Config.statusline.sourceSettingsPath)
} else {
    Join-Path $env:USERPROFILE '.claude\settings.json'
}
$backup = if ($Config.PSObject.Properties.Name -contains 'statusline' -and `
    $Config.statusline.PSObject.Properties.Name -contains 'backupBeforeApply') {
    [bool]$Config.statusline.backupBeforeApply
} else { $true }

Write-Host "  ソース     : $sourcePath" -ForegroundColor Gray
Write-Host "  ターゲット : ${LinuxHost}:~/.claude/settings.json" -ForegroundColor Gray
Write-Host "  バックアップ: $backup" -ForegroundColor Gray
Write-Host ""

try {
    $global = Get-GlobalStatusLineConfig -SettingsPath $sourcePath
}
catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not $global.found) {
    Write-Host "  [WARN] ソースの settings.json が存在しません: $sourcePath" -ForegroundColor Yellow
    Write-Host "  先に Windows 側で ClaudeCode の statusLine を設定してください。" -ForegroundColor Yellow
    exit 0
}

if ($null -eq $global.statusLine) {
    Write-Host "  [INFO] ソース settings.json に statusLine セクションがありません。" -ForegroundColor Yellow
    Write-Host "  ~/.claude/settings.json の statusLine を先に設定してください。" -ForegroundColor Yellow
    exit 0
}

Write-Host "  -- 適用内容のプレビュー --" -ForegroundColor Cyan
Write-Host ($global.statusLine | ConvertTo-Json -Depth 10) -ForegroundColor White
Write-Host ""

if (-not $NonInteractive) {
    $confirm = Read-Host "  Linux 側へ適用します。よろしいですか? [y/N]"
    if ($confirm -notmatch '^[yY]') {
        Write-Host "  キャンセルしました" -ForegroundColor Yellow
        exit 0
    }
}

try {
    $rc = Invoke-RemoteSettingsSync -LinuxHost $LinuxHost -StatusLine $global.statusLine -Backup:$backup
    if ($rc -eq 0) {
        Write-Host "  [OK] Statusline 設定を同期しました。" -ForegroundColor Green
        Write-Host "  次回 ClaudeCode 起動時から全プロジェクトで有効になります。" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  [ERROR] 同期に失敗 (exit=$rc)" -ForegroundColor Red
        exit $rc
    }
}
catch {
    Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
