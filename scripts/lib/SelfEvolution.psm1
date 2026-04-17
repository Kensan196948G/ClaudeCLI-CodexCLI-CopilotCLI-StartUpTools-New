# ============================================================
# SelfEvolution.psm1 - Self-evolution and session learning system
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.9.0
# Phase 3: Self Evolution System (Issue #50)
# ============================================================

Set-StrictMode -Version Latest

$script:EvolutionRecordSchema = @{
    version       = '1.0'
    session_id    = ''
    timestamp     = ''
    phase         = ''
    loop_number   = 0
    successes     = @()
    failures      = @()
    improvements  = @()
    lessons       = @()
    kpi_snapshot  = @{}
    next_actions  = @()
}

$script:DefaultEvolutionDir = Join-Path $env:USERPROFILE '.copilot' 'evolution'

function Get-EvolutionStorePath {
    [CmdletBinding()]
    param(
        [string]$BasePath = $script:DefaultEvolutionDir
    )

    if (-not (Test-Path $BasePath)) {
        New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
    }
    return $BasePath
}

function Save-EvolutionRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Phase,
        [int]$LoopNumber = 1,
        [string[]]$Successes = @(),
        [string[]]$Failures = @(),
        [string[]]$Improvements = @(),
        [string[]]$Lessons = @(),
        [hashtable]$KpiSnapshot = @{},
        [string[]]$NextActions = @(),
        [string]$StorePath = ''
    )

    $sessionId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
    $dateStr   = Get-Date -Format 'yyyyMMdd'

    $record = @{
        version      = '1.0'
        session_id   = $sessionId
        timestamp    = $timestamp
        phase        = $Phase
        loop_number  = $LoopNumber
        successes    = $Successes
        failures     = $Failures
        improvements = $Improvements
        lessons      = $Lessons
        kpi_snapshot = $KpiSnapshot
        next_actions = $NextActions
    }

    $storePath = if ($StorePath) { $StorePath } else { Get-EvolutionStorePath }
    $fileName  = "evolution_${dateStr}_${sessionId}.json"
    $filePath  = Join-Path $storePath $fileName

    $record | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8
    Write-Verbose "Evolution record saved: $filePath"

    return [pscustomobject]@{
        SessionId = $sessionId
        FilePath  = $filePath
        Timestamp = $timestamp
    }
}

function Get-EvolutionHistory {
    [CmdletBinding()]
    param(
        [string]$StorePath = '',
        [int]$Last = 10,
        [string]$Phase = ''
    )

    $storePath = if ($StorePath) { $StorePath } else { Get-EvolutionStorePath }

    if (-not (Test-Path $storePath)) {
        return @()
    }

    $files = Get-ChildItem -Path $storePath -Filter 'evolution_*.json' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First $Last

    $records = foreach ($file in $files) {
        $data = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($data) {
            if ($Phase -and $data.phase -ne $Phase) { continue }
            $data
        }
    }

    return $records
}

function Get-FrequentLessons {
    [CmdletBinding()]
    param(
        [string]$StorePath = '',
        [int]$TopN = 5
    )

    $history = Get-EvolutionHistory -StorePath $StorePath -Last 50
    if (-not $history) { return @() }

    $lessonCounts = @{}
    foreach ($record in $history) {
        if ($record.lessons) {
            foreach ($lesson in $record.lessons) {
                if ($lessonCounts.ContainsKey($lesson)) {
                    $lessonCounts[$lesson]++
                } else {
                    $lessonCounts[$lesson] = 1
                }
            }
        }
    }

    return $lessonCounts.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First $TopN |
        ForEach-Object { [pscustomobject]@{ Lesson = $_.Key; Count = $_.Value } }
}

function Invoke-SelfEvolutionCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Phase,
        [int]$LoopNumber = 1,
        [hashtable]$TestResults = @{},
        [hashtable]$CiResults = @{},
        [string[]]$CompletedTasks = @(),
        [string[]]$BlockedTasks = @(),
        [string]$StorePath = ''
    )

    Write-Host ""
    Write-Host "=== Self Evolution Cycle ===" -ForegroundColor Magenta
    Write-Host "Phase: $Phase | Loop: $LoopNumber"

    # 1. 振り返り分析
    $successes = @()
    $failures  = @()
    $lessons   = @()
    $nextActions = @()

    foreach ($task in $CompletedTasks) {
        $successes += "✅ $task"
    }
    foreach ($task in $BlockedTasks) {
        $failures += "❌ $task"
        $lessons  += "Blocked task '$task' should be decomposed into smaller units"
    }

    if ($TestResults.Count -gt 0) {
        $passed = $TestResults['Passed'] ?? 0
        $failed = $TestResults['Failed'] ?? 0
        if ($failed -eq 0) {
            $successes += "✅ Tests: $passed/$($passed + $failed) PASS"
        } else {
            $failures += "❌ Tests: $failed failed"
            $lessons  += "Test failures in loop $LoopNumber — investigate root cause before next iteration"
        }
    }

    if ($CiResults.Count -gt 0) {
        $ciStatus = $CiResults['Status'] ?? 'UNKNOWN'
        if ($ciStatus -eq 'SUCCESS') {
            $successes += "✅ CI: SUCCESS"
        } else {
            $failures += "❌ CI: $ciStatus"
            $lessons  += "CI failure must be resolved before merging"
        }
    }

    # 2. 改善提案生成
    $improvements = @()
    $history = Get-EvolutionHistory -StorePath $StorePath -Last 5 -Phase $Phase
    $prevFailures = $history | ForEach-Object { $_.failures } | Where-Object { $_ } | Select-Object -Unique

    foreach ($prev in $prevFailures) {
        if ($failures -contains $prev) {
            $improvements += "⚠️ 繰り返し失敗: $prev — ルール化・自動化を検討"
        }
    }

    if ($BlockedTasks.Count -gt 0) {
        $improvements += "📌 ブロックタスクを次ループ優先度P1に昇格"
    }

    if ($CompletedTasks.Count -gt 0 -and $BlockedTasks.Count -eq 0) {
        $improvements += "🚀 全タスク完了 — 次ループの範囲を拡大可能"
    }

    # 3. 次アクション決定
    if ($BlockedTasks.Count -gt 0) {
        $nextActions += "Debugger起動: $($BlockedTasks[0]) の原因分析"
    }
    if ($failures | Where-Object { $_ -match 'CI' }) {
        $nextActions += "CI Managerによる自動修復サイクル開始"
    }
    $nextActions += "次ループのMonitorフェーズで KPI再評価"

    # 4. KPIスナップショット
    $kpiSnapshot = @{
        completed_tasks = $CompletedTasks.Count
        blocked_tasks   = $BlockedTasks.Count
        test_passed     = $TestResults['Passed'] ?? 0
        test_failed     = $TestResults['Failed'] ?? 0
        ci_status       = $CiResults['Status'] ?? 'N/A'
        loop_number     = $LoopNumber
        phase           = $Phase
    }

    # 5. レコード保存
    $saved = Save-EvolutionRecord `
        -Phase $Phase `
        -LoopNumber $LoopNumber `
        -Successes $successes `
        -Failures $failures `
        -Improvements $improvements `
        -Lessons $lessons `
        -KpiSnapshot $kpiSnapshot `
        -NextActions $nextActions `
        -StorePath $StorePath

    # 6. 結果表示
    Write-Host ""
    Write-Host "--- 振り返り ---" -ForegroundColor Cyan
    foreach ($s in $successes) { Write-Host "  $s" -ForegroundColor Green }
    foreach ($f in $failures)  { Write-Host "  $f" -ForegroundColor Red }

    if ($improvements.Count -gt 0) {
        Write-Host ""
        Write-Host "--- 改善提案 ---" -ForegroundColor Yellow
        foreach ($i in $improvements) { Write-Host "  $i" }
    }

    if ($lessons.Count -gt 0) {
        Write-Host ""
        Write-Host "--- 学習事項 ---" -ForegroundColor Magenta
        foreach ($l in $lessons) { Write-Host "  📚 $l" }
    }

    Write-Host ""
    Write-Host "--- 次アクション ---" -ForegroundColor Cyan
    foreach ($n in $nextActions) { Write-Host "  👉 $n" }

    Write-Host ""
    Write-Host "[ SAVED ] Evolution record: $($saved.SessionId)" -ForegroundColor Green

    return [pscustomobject]@{
        SessionId    = $saved.SessionId
        Successes    = $successes
        Failures     = $failures
        Improvements = $improvements
        Lessons      = $lessons
        NextActions  = $nextActions
        KpiSnapshot  = $kpiSnapshot
        Passed       = ($failures.Count -eq 0)
    }
}

function Show-EvolutionSummary {
    [CmdletBinding()]
    param(
        [string]$StorePath = '',
        [int]$Last = 5
    )

    $history = Get-EvolutionHistory -StorePath $StorePath -Last $Last
    $topLessons = Get-FrequentLessons -StorePath $StorePath -TopN 3

    Write-Host ""
    Write-Host "=== Evolution Summary (Last $Last sessions) ===" -ForegroundColor Magenta

    if (-not $history -or $history.Count -eq 0) {
        Write-Host "  (履歴なし)"
        return
    }

    $totalSuccess = ($history | ForEach-Object { $_.successes.Count } | Measure-Object -Sum).Sum
    $totalFailure = ($history | ForEach-Object { $_.failures.Count } | Measure-Object -Sum).Sum
    $successRate  = if (($totalSuccess + $totalFailure) -gt 0) {
        [math]::Round($totalSuccess / ($totalSuccess + $totalFailure) * 100, 1)
    } else { 0 }

    Write-Host "  総セッション数: $($history.Count)"
    Write-Host "  成功率: $successRate% ($totalSuccess 成功 / $totalFailure 失敗)"

    if ($topLessons.Count -gt 0) {
        Write-Host ""
        Write-Host "  よく学んでいる教訓 TOP$($topLessons.Count):" -ForegroundColor Yellow
        foreach ($l in $topLessons) {
            Write-Host "    [$($l.Count)x] $($l.Lesson)"
        }
    }

    $latest = $history | Select-Object -First 1
    if ($latest) {
        Write-Host ""
        Write-Host "  最新セッション: $($latest.timestamp) (Phase: $($latest.phase))"
        if ($latest.next_actions) {
            Write-Host "  引継ぎアクション:"
            foreach ($a in $latest.next_actions) {
                Write-Host "    👉 $a"
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Save-EvolutionRecord'
    'Get-EvolutionHistory'
    'Get-FrequentLessons'
    'Invoke-SelfEvolutionCycle'
    'Show-EvolutionSummary'
    'Get-EvolutionStorePath'
)
