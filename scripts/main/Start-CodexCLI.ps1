<#
.SYNOPSIS
    [LEGACY] Codex CLI startup script
.DESCRIPTION
    LEGACY: v3.1.0 以降、ClaudeOS は Claude Code 専用に移行済み。
    このスクリプトは config.json の tools.codex.enabled=false により無効化されている。
    参照: docs/SOURCE_OF_TRUTH.md — Legacy 分類
    ClaudeOS-compatible manager-worker lane: Manager / Architect / Build / Review / Test.
#>

param(
    [string]$Project = '',
    [switch]$Local,
    [switch]$NonInteractive,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\Config.psm1') -Force

$ScriptRoot = Get-StartupRoot -PSScriptRootPath $PSScriptRoot
$ConfigPath = Get-StartupConfigPath -StartupRoot $ScriptRoot

function Write-Info { param($Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Ok { param($Message) Write-Host "[ OK ]  $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Error2 { param($Message) Write-Host "[ERR]   $Message" -ForegroundColor Red }

$launchContext = New-LauncherExecutionContext
$Config = $null

try {
    $Config = Import-LauncherConfig -ConfigPath $ConfigPath
    $toolConfig = $Config.tools.codex
    if (-not $toolConfig.enabled) {
        throw 'Codex CLI is disabled in config.json.'
    }

    $apiKeyName = $toolConfig.apiKeyEnvVar
    $apiKey = Get-LauncherApiKeyValue -ApiKeyName $apiKeyName -EnvMap $toolConfig.env
    if ([string]::IsNullOrEmpty($apiKey)) {
        Show-LauncherApiKeyWarning -ApiKeyName $apiKeyName -LoginHint 'Use codex --login if you rely on account auth.' -ApiHint "Set environment variable $apiKeyName for API auth."
    }

    Write-Info 'Checking Codex CLI...'
    if (-not (Assert-LauncherToolAvailable -Command 'codex' -InstallCommand $toolConfig.installCommand -ToolLabel 'Codex CLI' -NonInteractive:$NonInteractive)) {
        exit 1
    }
    Write-Ok 'Codex CLI is available.'

    $Local = Resolve-LauncherMode -Config $Config -Local:$Local -NonInteractive:$NonInteractive -ConfigPath $ConfigPath
    $linuxHost = $Config.linuxHost
    $linuxBase = $Config.linuxBase
    $Project = Resolve-LauncherProject -Config $Config -Project $Project -Local:$Local -NonInteractive:$NonInteractive -LinuxHost $linuxHost
    $modeName = Get-LauncherModeName -Local:$Local
    $launchContext.Project = $Project
    $launchContext.Mode = $modeName
    $launchContext.Tool = 'codex'
    $modeLabel = Get-LauncherModeLabel -Project $Project -Local:$Local -ProjectsDir $Config.projectsDir -LinuxHost $linuxHost -LinuxBase $linuxBase

    if (-not (Confirm-LauncherStart -ToolName 'Codex CLI' -Project $Project -ModeLabel $modeLabel -NonInteractive:$NonInteractive)) {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    if ($Local) {
        $localProjectDir = Join-Path $Config.projectsDir $Project
        Set-Location $localProjectDir
        Set-LauncherEnvironment -EnvMap $toolConfig.env
        if (-not [string]::IsNullOrEmpty($apiKey)) {
            [Environment]::SetEnvironmentVariable($apiKeyName, $apiKey, 'Process')
        }

        Sync-LauncherCodexGlobalConfig -StartupRoot $ScriptRoot -ProjectDir $localProjectDir

        if ($DryRun) {
            foreach ($line in (New-LauncherDryRunMessage -Command 'codex' -Arguments @($toolConfig.args) -WorkingDirectory $localProjectDir)) {
                Write-Info $line
            }
            $launchContext.Result = 'success'
            exit 0
        }

        # 起動通知音
        Invoke-LauncherNotificationSound -Tool 'codex' -Config $Config -Wait $false

        & codex @($toolConfig.args)
        $launchContext.Result = if ($LASTEXITCODE -eq 0) { 'success' } else { 'failure' }
        exit $LASTEXITCODE
    }

    $linuxProject = "$linuxBase/$Project"
    $codexArgs = $toolConfig.args -join ' '

    # ssh -tt HOST "cd PROJECT && codex ARGS" の直接コマンド
    $runScript = "cd '$linuxProject' && codex $codexArgs"

    if ($DryRun) {
        $dryRunLines = New-LauncherDryRunMessage -Command 'codex' -LinuxHost $linuxHost -RemoteScript $runScript
        Write-Info $dryRunLines[0]
        Write-Host $dryRunLines[1]
        $launchContext.Result = 'success'
        exit 0
    }

    # SSH起動通知音
    Invoke-LauncherNotificationSound -Tool 'codex' -Config $Config -Wait $false

    Write-Info "Connecting via SSH: $linuxHost"
    $sshExitCode = Invoke-LauncherSshScript -LinuxHost $linuxHost -RunScript $runScript -RemoteScriptName "run-codex-$Project.sh"
    # 255 は SSH 接続失敗（Invoke-LauncherSshScript 内で診断メッセージ表示済み）
    # それ以外の終了コードはツールの正常終了として扱う
    if ($sshExitCode -eq 255) {
        $launchContext.Result = 'failure'
        exit $sshExitCode
    }

    $launchContext.Result = 'success'
    Write-Ok 'Codex CLI session finished.'
}
catch {
    if ($_.Exception.Message -eq 'USER_CANCELLED') {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    $launchContext.Result = 'failure'
    Write-Error2 $_.Exception.Message
    exit 1
}
finally {
    if ($Config) {
        Complete-LauncherExecutionContext -Context $launchContext -Config $Config
    }
    # 終了通知音
    Invoke-LauncherNotificationSound -Tool 'codex' -Config $Config -Wait $true
}
