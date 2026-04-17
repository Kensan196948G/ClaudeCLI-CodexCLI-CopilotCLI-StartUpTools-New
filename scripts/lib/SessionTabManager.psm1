# ============================================================
# SessionTabManager.psm1 - セッション状態 (session.json) 管理
# ClaudeOS v3.1.0 / 情報タブ表示の single source of truth
# ============================================================

Set-StrictMode -Version Latest

function Get-SessionDir {
    param([string]$ConfigSessionsDir = '')

    if (-not [string]::IsNullOrWhiteSpace($ConfigSessionsDir)) {
        return [Environment]::ExpandEnvironmentVariables($ConfigSessionsDir)
    }
    return (Join-Path $env:USERPROFILE '.claudeos\sessions')
}

function New-SessionId {
    param(
        [Parameter(Mandatory)][string]$Project
    )
    $safe = $Project -replace '[^A-Za-z0-9_-]', '_'
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss')
    return "$stamp-$safe"
}

function New-SessionInfo {
    param(
        [Parameter(Mandatory)][string]$Project,
        [int]$DurationMinutes = 300,
        [ValidateSet('manual', 'cron')]
        [string]$Trigger = 'manual',
        [int]$ProcessId = 0,
        [string]$ConfigSessionsDir = ''
    )

    $sessionId = New-SessionId -Project $Project
    $start = Get-Date
    $end = $start.AddMinutes($DurationMinutes)

    $session = [pscustomobject]@{
        sessionId            = $sessionId
        project              = $Project
        trigger              = $Trigger
        start_time           = $start.ToString('o')
        max_duration_minutes = $DurationMinutes
        end_time_planned     = $end.ToString('o')
        status               = 'running'
        pid                  = $ProcessId
        last_updated         = $start.ToString('o')
    }

    $dir = Get-SessionDir -ConfigSessionsDir $ConfigSessionsDir
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    Save-SessionInfo -Session $session -ConfigSessionsDir $ConfigSessionsDir | Out-Null
    return $session
}

function Save-SessionInfo {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [string]$ConfigSessionsDir = ''
    )

    $dir = Get-SessionDir -ConfigSessionsDir $ConfigSessionsDir
    $path = Join-Path $dir ("{0}.json" -f $Session.sessionId)
    $tmpPath = "$path.tmp"

    # atomic rename: .tmp に書いてから Move-Item で上書き（部分書込み事故を防ぐ）
    $Session.last_updated = (Get-Date).ToString('o')
    $json = $Session | ConvertTo-Json -Depth 5
    Set-Content -Path $tmpPath -Value $json -Encoding UTF8
    Move-Item -Path $tmpPath -Destination $path -Force
    return $path
}

function Get-SessionInfo {
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$ConfigSessionsDir = ''
    )

    $dir = Get-SessionDir -ConfigSessionsDir $ConfigSessionsDir
    $path = Join-Path $dir "$SessionId.json"
    if (-not (Test-Path $path)) {
        return $null
    }
    return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Set-SessionStatus {
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)]
        [ValidateSet('running', 'completed', 'cancelled', 'exited', 'failed')]
        [string]$Status,
        [string]$ConfigSessionsDir = ''
    )

    $session = Get-SessionInfo -SessionId $SessionId -ConfigSessionsDir $ConfigSessionsDir
    if ($null -eq $session) { return $null }
    $session.status = $Status
    return (Save-SessionInfo -Session $session -ConfigSessionsDir $ConfigSessionsDir)
}

function Update-SessionDuration {
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][int]$DurationMinutes,
        [string]$ConfigSessionsDir = ''
    )

    $session = Get-SessionInfo -SessionId $SessionId -ConfigSessionsDir $ConfigSessionsDir
    if ($null -eq $session) { return $null }

    # 開始時刻起点で end_time_planned を再計算
    $start = [datetime]::Parse($session.start_time)
    $session.max_duration_minutes = $DurationMinutes
    $session.end_time_planned = $start.AddMinutes($DurationMinutes).ToString('o')
    return (Save-SessionInfo -Session $session -ConfigSessionsDir $ConfigSessionsDir)
}

function Get-ActiveSession {
    param([string]$ConfigSessionsDir = '')

    $dir = Get-SessionDir -ConfigSessionsDir $ConfigSessionsDir
    if (-not (Test-Path $dir)) { return $null }

    $latest = Get-ChildItem -Path $dir -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $s = Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $s.status -eq 'running'
            }
            catch { $false }
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $latest) { return $null }
    return (Get-Content $latest.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)
}

Export-ModuleMember -Function New-SessionInfo, Save-SessionInfo, Get-SessionInfo, `
    Set-SessionStatus, Update-SessionDuration, Get-ActiveSession, `
    Get-SessionDir, New-SessionId
