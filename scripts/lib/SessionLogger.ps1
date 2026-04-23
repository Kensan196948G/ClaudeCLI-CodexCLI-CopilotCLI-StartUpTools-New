<#
.SYNOPSIS
    Session logging, metadata, and audio notification functions extracted from LauncherCommon.psm1.
    Handles execution context tracking, JSONL log writes, and WinMM audio playback.
    Dot-sourced by LauncherCommon.psm1 for backward compatibility.
#>
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Records a launcher execution result to the recent projects history when the feature is enabled.
#>
function Write-LauncherExecutionResult {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [string]$Project,
        [Parameter(Mandatory)]
        [ValidateSet('claude', 'codex', 'copilot')]
        [string]$Tool,
        [Parameter(Mandatory)]
        [ValidateSet('local', 'ssh')]
        [string]$Mode,
        [Parameter(Mandatory)]
        [ValidateSet('success', 'failure', 'cancelled', 'unknown')]
        [string]$Result,
        [int]$ElapsedMs = 0
    )

    if (-not (Get-Command Update-RecentProject -ErrorAction SilentlyContinue)) {
        return
    }

    if ($null -eq $Config.recentProjects -or -not $Config.recentProjects.enabled -or [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile)) {
        return
    }

    Update-RecentProject `
        -ProjectName $Project `
        -Tool $Tool `
        -Mode $Mode `
        -Result $Result `
        -ElapsedMs $ElapsedMs `
        -HistoryPath $Config.recentProjects.historyFile `
        -MaxHistory $Config.recentProjects.maxHistory
}

<#
.SYNOPSIS
    Returns the path to today's launch metadata JSONL log file derived from the Config logging or history settings.
#>
function Get-LauncherMetadataLogPath {
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    if ($Config.logging -and -not [string]::IsNullOrWhiteSpace($Config.logging.logDir)) {
        return (Join-Path $Config.logging.logDir ("launch-metadata-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd')))
    }

    if ($Config.recentProjects -and -not [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile)) {
        $historyDir = Split-Path -Parent ([Environment]::ExpandEnvironmentVariables($Config.recentProjects.historyFile))
        if (-not [string]::IsNullOrWhiteSpace($historyDir)) {
            return (Join-Path $historyDir ("launch-metadata-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd')))
        }
    }

    return $null
}

<#
.SYNOPSIS
    Reads and returns recent launcher metadata entries from the JSONL log files in the log directory.
#>
function Get-LauncherMetadataEntry {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [int]$MaxCount = 20
    )

    $logPath = Get-LauncherMetadataLogPath -Config $Config
    if ([string]::IsNullOrWhiteSpace($logPath)) {
        return @()
    }

    $logDir = Split-Path -Parent $logPath
    if ([string]::IsNullOrWhiteSpace($logDir) -or -not (Test-Path $logDir)) {
        return @()
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-ChildItem -Path $logDir -Filter 'launch-metadata-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    foreach ($file in $files) {
        foreach ($line in @(Get-Content -Path $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            try {
                $entries.Add(($line | ConvertFrom-Json))
            }
            catch {
                Write-Debug "Skipping malformed JSON history entry: $_"
            }
            if ($entries.Count -ge $MaxCount) {
                break
            }
        }
        if ($entries.Count -ge $MaxCount) {
            break
        }
    }

    return @(
        $entries |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First $MaxCount
    )
}

<#
.SYNOPSIS
    Reads TASKS.md and returns a summary of pending task count and priority distribution.
#>
function Get-LauncherBacklogSummary {
    param(
        [string]$TasksPath = (Join-Path (Get-Location) 'TASKS.md')
    )

    if (-not (Test-Path $TasksPath)) {
        return [pscustomobject]@{
            Count = 0
            Priorities = @()
        }
    }

    $tasks = @(Get-Content -Path $TasksPath -Encoding UTF8 | Where-Object {
        $_ -match '^\d+\.\s' -and $_ -notmatch '\[DONE\]'
    })
    $priorities = @(
        $tasks |
            ForEach-Object {
                if ($_ -match '\[Priority:([^\]]+)\]') { $Matches[1] }
            } |
            Where-Object { $_ } |
            Group-Object |
            Sort-Object Name |
            ForEach-Object { "{0}:{1}" -f $_.Name, $_.Count }
    )

    return [pscustomobject]@{
        Count = $tasks.Count
        Priorities = $priorities
    }
}

<#
.SYNOPSIS
    Appends a launcher metadata entry as a JSON line to today's metadata log file with write-lock retry.
#>
function Write-LauncherMetadataLog {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [Parameter(Mandatory)]
        [pscustomobject]$Entry
    )

    $logPath = Get-LauncherMetadataLogPath -Config $Config
    if ([string]::IsNullOrWhiteSpace($logPath)) {
        return
    }

    $logDir = Split-Path -Parent $logPath
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $line = $Entry | ConvertTo-Json -Compress -Depth 6

    # 複数インスタンスが同時に書き込むと IOException が発生する。
    # 最大5回リトライして競合を回避する。
    $maxRetries = 5
    $retryDelay = 50  # ms
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            $stream = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $writer = [System.IO.StreamWriter]::new($stream, [System.Text.Encoding]::UTF8)
                $writer.WriteLine($line)
                $writer.Flush()
            }
            finally {
                $stream.Close()
            }
            break
        }
        catch [System.IO.IOException] {
            if ($i -lt ($maxRetries - 1)) {
                Start-Sleep -Milliseconds $retryDelay
            }
            # 最終リトライも失敗した場合はログ書き込みをスキップ（起動をブロックしない）
        }
    }
}

<#
.SYNOPSIS
    Creates a new execution context object used to track a launcher session's timing, tool, mode, and result.
#>
function New-LauncherExecutionContext {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Factory function returns in-memory object; no persistent system state is modified')]
    param()
    return [pscustomobject]@{
        StartTime = Get-Date
        Result = 'unknown'
        Project = $null
        Mode = $null
        Tool = $null
    }
}

<#
.SYNOPSIS
    Finalizes an execution context by writing the result and elapsed time to the execution log.
#>
function Complete-LauncherExecutionContext {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Context,
        [Parameter(Mandatory)]
        [object]$Config
    )

    if (-not $Context.Project -or -not $Context.Mode -or -not $Context.Tool) {
        return
    }

    $elapsedMs = [int][Math]::Max(0, ((Get-Date) - $Context.StartTime).TotalMilliseconds)
    Write-LauncherExecutionResult -Config $Config -Project $Context.Project -Tool $Context.Tool -Mode $Context.Mode -Result $Context.Result -ElapsedMs $elapsedMs
    Write-LauncherMetadataLog -Config $Config -Entry ([pscustomobject]@{
        timestamp = (Get-Date).ToString('o')
        project = $Context.Project
        tool = $Context.Tool
        mode = $Context.Mode
        result = $Context.Result
        elapsedMs = $elapsedMs
        host = if ($Config.linuxHost) { $Config.linuxHost } else { $env:COMPUTERNAME }
    })
}

<#
.SYNOPSIS
    Computes a summary (total runs, success rate, average elapsed time) from a collection of recent entries.
#>
function Get-LauncherRecentSummary {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries
    )

    $total = @($Entries).Count
    if ($total -eq 0) {
        return [pscustomobject]@{
            Total = 0
            SuccessRate = 0
            AverageElapsedMs = 0
        }
    }

    $successCount = @($Entries | Where-Object { $_.result -eq 'success' }).Count
    $elapsedEntries = @($Entries | Where-Object { $null -ne $_.elapsedMs })
    $avgElapsed = if ($elapsedEntries.Count -gt 0) {
        [int](($elapsedEntries | Measure-Object -Property elapsedMs -Average).Average)
    }
    else {
        0
    }

    return [pscustomobject]@{
        Total = $total
        SuccessRate = [int][Math]::Round(($successCount / $total) * 100)
        AverageElapsedMs = $avgElapsed
    }
}

<#
.SYNOPSIS
    Returns per-tool statistics (runs, success rate, average elapsed time, latest result) from recent entries.
#>
function Get-LauncherToolStatistic {
    param(
        [AllowEmptyCollection()]
        [object[]]$Entries = @(),
        [string[]]$Tools = @('claude', 'codex', 'copilot')
    )

    $stats = [System.Collections.Generic.List[object]]::new()
    foreach ($tool in $Tools) {
        $toolEntries = @($Entries | Where-Object { $_.tool -eq $tool })
        $summary = Get-LauncherRecentSummary -Entries $toolEntries
        $latest = @(
            $toolEntries |
                Sort-Object @{ Expression = {
                    if ($_.timestamp) {
                        try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                    }
                    else {
                        [datetimeoffset]::MinValue
                    }
                }; Descending = $true } |
                Select-Object -First 1
        )
        $stats.Add([pscustomobject]@{
            tool = $tool
            runs = $summary.Total
            successRate = $summary.SuccessRate
            averageElapsedMs = $summary.AverageElapsedMs
            lastResult = if ($latest.Count -gt 0 -and $latest[0].result) { $latest[0].result } else { 'none' }
            lastProject = if ($latest.Count -gt 0) { $latest[0].project } else { $null }
            lastTimestamp = if ($latest.Count -gt 0) { $latest[0].timestamp } else { $null }
        })
    }

    return @($stats)
}

<#
.SYNOPSIS
    Builds Architect, QA, and Ops lane event summaries from recent metadata entries and the backlog summary.
#>
function Get-LauncherAgentLaneEvent {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [AllowEmptyCollection()]
        [object[]]$MetadataEntries = @(),
        [AllowNull()]
        [object]$BacklogSummary = $null
    )

    $architectLatest = @(
        $MetadataEntries |
            Where-Object { $_.tool -in @('claude', 'codex') } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 1
    )
    $opsLatest = @(
        $MetadataEntries |
            Where-Object { $_.tool -eq 'copilot' } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 1
    )
    $overallSummary = Get-LauncherRecentSummary -Entries $MetadataEntries
    $priorityLabel = if ($BacklogSummary -and @($BacklogSummary.Priorities).Count -gt 0) { @($BacklogSummary.Priorities) -join ', ' } else { 'none' }

    $recentArchitectEvents = @(
        $MetadataEntries |
            Where-Object { $_.tool -in @('claude', 'codex') } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 3
    )
    $recentOpsEvents = @(
        $MetadataEntries |
            Where-Object { $_.tool -eq 'copilot' } |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 3
    )
    $recentQaEvents = @(
        $MetadataEntries |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First 3
    )

    $architectRecentLabel = @($recentArchitectEvents | ForEach-Object { '{0}:{1}' -f $_.project, $_.result }) -join ', '
    $qaRecentLabel = @($recentQaEvents | ForEach-Object { '{0}/{1}' -f $_.tool, $_.result }) -join ', '
    $opsRecentLabel = @($recentOpsEvents | ForEach-Object { '{0}:{1}' -f $_.project, $_.result }) -join ', '

    return @(
        [pscustomobject]@{
            lane = 'Architect'
            message = if ($architectLatest.Count -gt 0) {
                "latest=$($architectLatest[0].tool)/$($architectLatest[0].project) result=$($architectLatest[0].result) recent=$architectRecentLabel"
            }
            else {
                "defaultTool=$($Config.tools.defaultTool) recent=none"
            }
        },
        [pscustomobject]@{
            lane = 'QA'
            message = "runs=$($overallSummary.Total) success=$($overallSummary.SuccessRate)% avg=$($overallSummary.AverageElapsedMs)ms recent=$qaRecentLabel"
        },
        [pscustomobject]@{
            lane = 'Ops'
            message = if ($opsLatest.Count -gt 0) {
                "backlog=$($BacklogSummary.Count) priorities=$priorityLabel lastCopilot=$($opsLatest[0].result) recent=$opsRecentLabel"
            }
            else {
                "backlog=$($BacklogSummary.Count) priorities=$priorityLabel lastCopilot=none"
            }
        }
    )
}

<#
.SYNOPSIS
    Returns the current token budget zone and status message based on the AI_STARTUP_TOKEN_USAGE_PCT environment variable.
#>
function Get-LauncherTokenBudgetStatus {
    $pct = if ($env:AI_STARTUP_TOKEN_USAGE_PCT) { [int]$env:AI_STARTUP_TOKEN_USAGE_PCT } else { -1 }
    if ($pct -lt 0) {
        return [pscustomobject]@{ Percent = $null; Zone = 'Unknown'; Status = 'Token usage unavailable' }
    }
    if ($pct -lt 60) {
        return [pscustomobject]@{ Percent = $pct; Zone = 'Green'; Status = 'Normal development' }
    }
    if ($pct -lt 75) {
        return [pscustomobject]@{ Percent = $pct; Zone = 'Yellow'; Status = 'Reduced build activity' }
    }
    if ($pct -lt 90) {
        return [pscustomobject]@{ Percent = $pct; Zone = 'Orange'; Status = 'Monitor priority' }
    }

    return [pscustomobject]@{ Percent = $pct; Zone = 'Red'; Status = 'Development stop threshold' }
}

<#
.SYNOPSIS
    Returns recent project entries from the history file when the recentProjects feature is enabled.
#>
function Get-LauncherRecentEntry {
    param(
        [Parameter(Mandatory)]
        [object]$Config,
        [int]$MaxCount = 20
    )

    if (-not (Get-Command Get-RecentProject -ErrorAction SilentlyContinue)) {
        return @()
    }
    if ($null -eq $Config.recentProjects -or -not $Config.recentProjects.enabled -or [string]::IsNullOrWhiteSpace($Config.recentProjects.historyFile)) {
        return @()
    }

    return @(
        Get-RecentProject -HistoryPath $Config.recentProjects.historyFile |
            Sort-Object @{ Expression = {
                if ($_.timestamp) {
                    try { [datetimeoffset]$_.timestamp } catch { [datetimeoffset]::MinValue }
                }
                else {
                    [datetimeoffset]::MinValue
                }
            }; Descending = $true } |
            Select-Object -First $MaxCount
    )
}

<#
.SYNOPSIS
    Returns the most recent result, elapsed time, and timestamp for each tool from the provided entry list.
#>
function Get-LauncherRecentToolResult {
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries,
        [string[]]$Tools = @('claude', 'codex', 'copilot')
    )

    $results = @()
    foreach ($tool in $Tools) {
        $latest = @($Entries | Where-Object { $_.tool -eq $tool } | Select-Object -First 1)
        if ($latest.Count -eq 0) {
            $results += [pscustomobject]@{
                tool = $tool
                result = 'none'
                elapsedMs = $null
                timestamp = $null
            }
            continue
        }

        $results += [pscustomobject]@{
            tool = $tool
            result = if ($latest[0].result) { $latest[0].result } else { 'unknown' }
            elapsedMs = $latest[0].elapsedMs
            timestamp = $latest[0].timestamp
        }
    }

    return @($results)
}

# WinMM type definition is loaded lazily inside Invoke-LauncherNotificationSound

function Invoke-LauncherNotificationSound {
    <#
    .SYNOPSIS
        通知音を再生する。MP3/WAV に対応し、ウィンドウを開かずバックグラウンドで再生する。
    .PARAMETER Tool
        ツール名 (claude / codex / copilot)。config.json の notifications.sounds からパスを取得。
    .PARAMETER Config
        Import-LauncherConfig で読み込んだ設定オブジェクト。
    .PARAMETER Wait
        $true の場合、音の再生が完了するまでブロックする（終了通知向け）。
        $false の場合はノンブロッキング（起動通知向け）。デフォルト $false。
    #>
    param(
        [string]$Tool = 'claude',
        [object]$Config,
        [bool]$Wait = $false
    )

    if ($null -eq $Config) { return }
    # StrictMode 対応: PSObject.Properties 経由で安全にアクセス
    $notifProp = $Config.PSObject.Properties['notifications']
    if ($null -eq $notifProp) { return }
    $notif = $notifProp.Value
    if ($null -eq $notif -or -not $notif.soundEnabled) { return }

    # ツール別サウンドパスを取得。個別設定がなければ共通パスにフォールバック。
    $soundPath = $null
    if ($notif.sounds -and $notif.sounds.PSObject.Properties[$Tool]) {
        $soundPath = $notif.sounds.PSObject.Properties[$Tool].Value
    }
    if ([string]::IsNullOrWhiteSpace($soundPath)) { return }
    $soundPath = [Environment]::ExpandEnvironmentVariables($soundPath)
    if (-not (Test-Path $soundPath)) {
        Write-Warning "[Sound] ファイルが見つかりません: $soundPath"
        return
    }

    try {
        # WinMM MCI API 型定義（初回呼び出し時のみ）
        if (-not ([System.Management.Automation.PSTypeName]'LauncherWinMM').Type) {
            Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class LauncherWinMM {
    [DllImport("winmm.dll", CharSet = CharSet.Auto)]
    public static extern int mciSendString(string lpstrCommand, StringBuilder lpstrReturnString, int uReturnLength, IntPtr hwndCallback);
}
'@ -ErrorAction SilentlyContinue
        }
        if (-not ([System.Management.Automation.PSTypeName]'LauncherWinMM').Type) { return }

        $alias = "launcher_notif_$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
        $escaped = $soundPath -replace '"', ''

        [void][LauncherWinMM]::mciSendString("open `"$escaped`" alias $alias", $null, 0, [IntPtr]::Zero)
        if ($Wait) {
            [void][LauncherWinMM]::mciSendString("play $alias wait", $null, 0, [IntPtr]::Zero)
            [void][LauncherWinMM]::mciSendString("close $alias", $null, 0, [IntPtr]::Zero)
        } else {
            [void][LauncherWinMM]::mciSendString("play $alias", $null, 0, [IntPtr]::Zero)
            # ノンブロッキングの場合、8秒後にバックグラウンドでクローズ
            $localAlias = $alias
            $null = [System.Threading.Tasks.Task]::Run([Action]{
                Start-Sleep -Milliseconds 8000
                try { [void][LauncherWinMM]::mciSendString("close $localAlias", $null, 0, [IntPtr]::Zero) } catch { Write-Debug "Audio close failed for '$localAlias': $_" }
            })
        }
    }
    catch {
        # 音声再生の失敗はサイレントに無視（起動をブロックしない）
        Write-Debug "Audio playback failed (suppressed to avoid blocking startup): $_"
    }
}
