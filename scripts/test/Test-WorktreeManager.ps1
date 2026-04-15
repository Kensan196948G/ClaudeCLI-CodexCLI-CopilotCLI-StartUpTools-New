# ============================================================
# Test-WorktreeManager.ps1 - Worktree Manager interactive test
# Start-Menu entry point for menu option
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $ProjectRoot "scripts\lib\WorktreeManager.psm1") -Force

Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "  Worktree Manager - 状態確認" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""

try {
    $summary = Get-WorktreeSummary -RepoRoot $ProjectRoot

    if ($summary.Count -eq 0) {
        Write-Host "  Worktree が見つかりません。" -ForegroundColor Yellow
    }
    else {
        Write-Host "  登録済み Worktree: $($summary.Count) 件" -ForegroundColor Green
        Write-Host ""

        foreach ($wt in $summary) {
            $color = if ($wt.Label -eq '[MAIN]') { 'Green' } else { 'Yellow' }
            $label = if ($wt.Label) { " $($wt.Label)" } else { '' }
            Write-Host "    $($wt.Branch)$label" -ForegroundColor $color
            Write-Host "      Commit: $($wt.Commit)" -ForegroundColor DarkGray
            Write-Host "      Path:   $($wt.Path)" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  完了" -ForegroundColor Green
}
catch {
    Write-Host "  エラー: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
