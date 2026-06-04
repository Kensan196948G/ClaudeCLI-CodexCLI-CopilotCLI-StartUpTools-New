#Requires -Version 5.1
<#
.SYNOPSIS
    タスクスケジューラーから呼ばれる Supervisor Daemon 起動ラッパー。
    PID ファイルによる二重起動防止・ログ出力を行う。
.NOTES
    Register-SupervisorTask.ps1 の WrapperPs1 として登録される。
    ポートを持たない supervisor は ~/.claudeos/supervisor/supervisor.pid で生死判定する。
#>

$ScriptRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$DaemonJs     = Join-Path $ScriptRoot 'scripts\dashboards\supervisor-daemon.js'
$SupervisDir  = Join-Path $env:USERPROFILE '.claudeos\supervisor'
$PidFile      = Join-Path $SupervisDir 'supervisor.pid'
$LogFile      = Join-Path $SupervisDir 'supervisor.log'

# ログディレクトリ確保
if (-not (Test-Path $SupervisDir)) { New-Item -ItemType Directory -Path $SupervisDir -Force | Out-Null }

function Write-SupLog {
    param([string]$Msg)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Msg"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

Write-SupLog "=== Supervisor task start ==="

# 二重起動防止: PID ファイルが存在し、プロセスが生きていれば起動しない
if (Test-Path $PidFile) {
    $existingPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($existingPid -and ($existingPid -match '^\d+$')) {
        $intPid = [int]$existingPid
        $proc   = Get-Process -Id $intPid -ErrorAction SilentlyContinue
        if ($proc) {
            Write-SupLog "PID $intPid already running (name=$($proc.Name)). Skip."
            exit 0
        } else {
            Write-SupLog "Stale PID file ($intPid). Overwriting."
        }
    }
}

# node が見つからなければ終了
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-SupLog "ERROR: node.exe not found"
    exit 1
}

if (-not (Test-Path $DaemonJs)) {
    Write-SupLog "ERROR: supervisor-daemon.js not found at $DaemonJs"
    exit 1
}

Write-SupLog "Starting: node $DaemonJs (detached)"

try {
    $logOut = "${LogFile}.out"
    $proc   = Start-Process `
        -FilePath     $node.Source `
        -ArgumentList "`"$DaemonJs`"" `
        -WorkingDirectory $ScriptRoot `
        -WindowStyle  Hidden `
        -RedirectStandardOutput $logOut `
        -RedirectStandardError  "${LogFile}.err" `
        -PassThru

    if ($proc) {
        Set-Content -Path $PidFile -Value $proc.Id -Encoding UTF8
        Write-SupLog "Started: PID=$($proc.Id)"
        Write-SupLog "State: $SupervisDir\state.json"
    } else {
        Write-SupLog "ERROR: Start-Process returned null"
        exit 1
    }
} catch {
    Write-SupLog "ERROR: $_"
    exit 1
}

Write-SupLog "=== Supervisor task launcher end (node continues in background) ==="
