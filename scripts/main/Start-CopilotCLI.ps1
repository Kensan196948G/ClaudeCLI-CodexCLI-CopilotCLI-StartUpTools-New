<#
.SYNOPSIS
    [LEGACY] GitHub Copilot CLI startup script.
.DESCRIPTION
    LEGACY: v3.1.0 以降、ClaudeOS は Claude Code 専用に移行済み。
    このスクリプトは config.json の tools.copilot.enabled=false により無効化されている。
    参照: docs/SOURCE_OF_TRUTH.md — Legacy 分類
    ClaudeOS-compatible custom-agent lane entry for Main / Task / Code Review / Ops.
    See docs/common/08_AgentTeams対応表.md for the mapping table.
#>

param(
    [string]$Project = '',
    [switch]$Local,
    [switch]$NonInteractive,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StartupRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $StartupRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $StartupRoot 'scripts\lib\Config.psm1') -Force

$ConfigPath = Get-StartupConfigPath -StartupRoot $StartupRoot

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "[ OK ] $Message" -ForegroundColor Green }
function Write-Err { param([string]$Message) Write-Host "[ERR ] $Message" -ForegroundColor Red }

$launchContext = New-LauncherExecutionContext
$config = $null

try {
    $config = Import-LauncherConfig -ConfigPath $ConfigPath
    $toolConfig = $config.tools.copilot
    if (-not $toolConfig.enabled) {
        throw 'GitHub Copilot CLI is disabled in config.json.'
    }

    $command = if ([string]::IsNullOrWhiteSpace($toolConfig.command)) { 'copilot' } else { "$($toolConfig.command)" }
    $arguments = if ($null -ne $toolConfig.args) { @($toolConfig.args | ForEach-Object { "$_" }) } else { @('--yolo') }

    if ($Local) {
        Write-Info 'Checking GitHub Copilot CLI availability...'
        if (-not (Assert-LauncherToolAvailable -Command $command -InstallCommand $toolConfig.installCommand -ToolLabel 'GitHub Copilot CLI' -NonInteractive:$NonInteractive)) {
            exit 1
        }
        Write-Ok 'GitHub Copilot CLI command is available.'
    }

    $Local = Resolve-LauncherMode -Config $config -Local:$Local -NonInteractive:$NonInteractive -ConfigPath $ConfigPath
    $Project = Resolve-LauncherProject -Config $config -Project $Project -Local:$Local -NonInteractive:$NonInteractive
    $modeName = Get-LauncherModeName -Local:$Local
    $modeLabel = Get-LauncherModeLabel -Project $Project -Local:$Local -ProjectsDir $config.projectsDir

    $launchContext.Project = $Project
    $launchContext.Mode = $modeName
    $launchContext.Tool = 'copilot'

    if (-not (Confirm-LauncherStart -ToolName 'GitHub Copilot CLI' -Project $Project -ModeLabel $modeLabel -NonInteractive:$NonInteractive)) {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    if ($Local) {
        $projectDir = Join-Path $config.projectsDir $Project
        if (-not (Test-Path $projectDir)) {
            throw "Project directory not found: $projectDir"
        }

        Write-Info "Starting GitHub Copilot CLI locally for $Project"
        Set-Location $projectDir
        Set-LauncherEnvironment -EnvMap $toolConfig.env
        Sync-LauncherCopilotGlobalConfig -StartupRoot $StartupRoot -ProjectDir $projectDir

        if ($DryRun) {
            foreach ($line in (New-LauncherDryRunMessage -Command $command -Arguments $arguments -WorkingDirectory $projectDir)) {
                Write-Info $line
            }
            $launchContext.Result = 'success'
            exit 0
        }

        # 起動通知音
        Invoke-LauncherNotificationSound -Tool 'copilot' -Config $config -Wait $false

        # Start-Process -NoNewWindow -Wait を使用してコンソール制御を正しく渡す
        # & $command @arguments では PowerShell の引数展開が問題を引き起こす場合がある
        $process = Start-Process -FilePath $command -ArgumentList $arguments `
            -WorkingDirectory $projectDir -NoNewWindow -Wait -PassThru
        $exitCode = if ($null -ne $process -and $null -ne $process.ExitCode) { $process.ExitCode } else { 0 }
        $launchContext.Result = if ($exitCode -eq 0) { 'success' } else { 'failure' }
        exit $exitCode
    }
}
catch {
    if ($_.Exception.Message -eq 'USER_CANCELLED') {
        Write-Info 'Cancelled.'
        $launchContext.Result = 'cancelled'
        exit 0
    }

    $launchContext.Result = 'failure'
    Write-Err $_.Exception.Message
    exit 1
}
finally {
    if ($null -ne $config) {
        Complete-LauncherExecutionContext -Context $launchContext -Config $config
    }
    # 終了通知音
    Invoke-LauncherNotificationSound -Tool 'copilot' -Config $config -Wait $true
}
