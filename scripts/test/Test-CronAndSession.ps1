<#
.SYNOPSIS
    CronManager / SessionTabManager のスモークテスト (v3.1.0)
.DESCRIPTION
    SSH を伴わない純粋関数 (Format-CronExpression, New-CronEntryId) と、
    SessionTabManager のローカルファイル CRUD を検証する。
    Pester 非依存で実行可能。
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ScriptRoot 'scripts\lib\CronManager.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $ScriptRoot 'scripts\lib\SessionTabManager.psm1') -Force -DisableNameChecking

$script:Total = 0
$script:Passed = 0
$script:Failed = @()

function Assert-Eq {
    param($Expected, $Actual, [string]$Label)
    $script:Total++
    if ($Expected -eq $Actual) {
        $script:Passed++
        Write-Host "  [OK]   $Label" -ForegroundColor Green
    }
    else {
        $script:Failed += $Label
        Write-Host "  [FAIL] $Label" -ForegroundColor Red
        Write-Host "         期待値: $Expected" -ForegroundColor DarkGray
        Write-Host "         実際値: $Actual" -ForegroundColor DarkGray
    }
}

function Assert-Match {
    param([string]$Pattern, [string]$Actual, [string]$Label)
    $script:Total++
    if ($Actual -match $Pattern) {
        $script:Passed++
        Write-Host "  [OK]   $Label" -ForegroundColor Green
    }
    else {
        $script:Failed += $Label
        Write-Host "  [FAIL] $Label (pattern=$Pattern, actual=$Actual)" -ForegroundColor Red
    }
}

function Assert-Throws {
    param([scriptblock]$Block, [string]$Label)
    $script:Total++
    try {
        & $Block
        $script:Failed += $Label
        Write-Host "  [FAIL] $Label (例外が発生しなかった)" -ForegroundColor Red
    }
    catch {
        $script:Passed++
        Write-Host "  [OK]   $Label" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== CronManager テスト ===" -ForegroundColor Cyan

Assert-Eq '0 21 * * 0' (Format-CronExpression -DayOfWeek @(0) -Time '21:00') 'Format-CronExpression: 日曜 21:00'
Assert-Eq '30 9 * * 1,3,5' (Format-CronExpression -DayOfWeek @(1, 3, 5) -Time '09:30') 'Format-CronExpression: 月水金 9:30'
Assert-Eq '0 0 * * 0,1,2,3,4,5,6' (Format-CronExpression -DayOfWeek @(0, 1, 2, 3, 4, 5, 6) -Time '00:00') 'Format-CronExpression: 毎日 0:00'
Assert-Throws { Format-CronExpression -DayOfWeek @(0) -Time '25:00' } 'Format-CronExpression: 不正時刻で例外'
Assert-Throws { Format-CronExpression -DayOfWeek @(7) -Time '10:00' } 'Format-CronExpression: 不正曜日で例外'
Assert-Throws { Format-CronExpression -DayOfWeek @(0) -Time 'abc' } 'Format-CronExpression: 文字列時刻で例外'

$id1 = New-CronEntryId
$id2 = New-CronEntryId
Assert-Match '^[0-9a-f]{8}$' $id1 'New-CronEntryId: 8桁16進'
Assert-Eq $true ($id1 -ne $id2) 'New-CronEntryId: ユニーク'

Assert-Eq '日' (Get-DayOfWeekLabel -Dow 0) 'Get-DayOfWeekLabel: 0=日'
Assert-Eq '土' (Get-DayOfWeekLabel -Dow 6) 'Get-DayOfWeekLabel: 6=土'

Write-Host ""
Write-Host "=== SessionTabManager テスト ===" -ForegroundColor Cyan

# 一時ディレクトリで CRUD 検証
$tmpDir = Join-Path $env:TEMP ("claudeos-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
try {
    $sess = New-SessionInfo -Project 'test-proj' -DurationMinutes 60 -Trigger 'manual' -Pid 12345 -ConfigSessionsDir $tmpDir
    Assert-Match 'test-proj' $sess.sessionId 'New-SessionInfo: sessionId にプロジェクト名'
    Assert-Eq 60 $sess.max_duration_minutes 'New-SessionInfo: duration 保存'
    Assert-Eq 'running' $sess.status 'New-SessionInfo: 初期 status=running'
    Assert-Eq 'manual' $sess.trigger 'New-SessionInfo: trigger=manual'

    $loaded = Get-SessionInfo -SessionId $sess.sessionId -ConfigSessionsDir $tmpDir
    Assert-Eq $sess.sessionId $loaded.sessionId 'Get-SessionInfo: ラウンドトリップ'

    Update-SessionDuration -SessionId $sess.sessionId -DurationMinutes 120 -ConfigSessionsDir $tmpDir | Out-Null
    $updated = Get-SessionInfo -SessionId $sess.sessionId -ConfigSessionsDir $tmpDir
    Assert-Eq 120 $updated.max_duration_minutes 'Update-SessionDuration: 120 分に変更'

    # end_time_planned が start_time + 120 分になっていることを確認
    $start = [datetime]::Parse($updated.start_time)
    $end = [datetime]::Parse($updated.end_time_planned)
    $diffMin = [int]($end - $start).TotalMinutes
    Assert-Eq 120 $diffMin 'Update-SessionDuration: end_time_planned 再計算'

    Set-SessionStatus -SessionId $sess.sessionId -Status 'completed' -ConfigSessionsDir $tmpDir | Out-Null
    $completed = Get-SessionInfo -SessionId $sess.sessionId -ConfigSessionsDir $tmpDir
    Assert-Eq 'completed' $completed.status 'Set-SessionStatus: completed'

    # Get-ActiveSession は running 限定なので completed 後は null
    $active = Get-ActiveSession -ConfigSessionsDir $tmpDir
    Assert-Eq $true ($null -eq $active) 'Get-ActiveSession: completed 後は null'
}
finally {
    Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 結果: $script:Passed / $script:Total 件成功" -ForegroundColor $(if ($script:Failed.Count -eq 0) { 'Green' } else { 'Red' })
Write-Host "==========================================" -ForegroundColor Cyan

if ($script:Failed.Count -gt 0) {
    Write-Host ""
    Write-Host "失敗:" -ForegroundColor Red
    foreach ($f in $script:Failed) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
exit 0
