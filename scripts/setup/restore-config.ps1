# ============================================================
# restore-config.ps1
# config.jsonバックアップファイルから設定を復元
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$BackupFile = ""
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConfigPath = Join-Path $RootDir "config\config.json"
$BackupDir = Join-Path $RootDir "config\backups"

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "🔄 config.json 復元スクリプト"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""

# バックアップディレクトリ存在確認
if (-not (Test-Path $BackupDir)) {
    Write-Error "❌ バックアップディレクトリが見つかりません: $BackupDir"
}

# 利用可能なバックアップ一覧
$AvailableBackups = @(
    Get-ChildItem -Path $BackupDir -Filter "config_*.json" -ErrorAction SilentlyContinue
    Get-ChildItem -Path $BackupDir -Filter "config-*.json" -ErrorAction SilentlyContinue
) | Sort-Object LastWriteTime -Descending

if ($AvailableBackups.Count -eq 0) {
    Write-Error "❌ バックアップファイルが見つかりません"
}

Write-Host "📦 利用可能なバックアップ ($($AvailableBackups.Count)件):`n"
for ($i = 0; $i -lt [Math]::Min(10, $AvailableBackups.Count); $i++) {
    $backup = $AvailableBackups[$i]
    $ageStr = if (($backup.LastWriteTime - (Get-Date)).TotalHours -gt -24) {
        "$(([int](-(($backup.LastWriteTime - (Get-Date)).TotalHours))))時間前"
    } else {
        "$([int](-(($backup.LastWriteTime - (Get-Date)).TotalDays)))日前"
    }
    Write-Host "[$($i+1)] $($backup.Name) ($ageStr)"
}
Write-Host ""

# バックアップファイル選択
if ($BackupFile) {
    $SelectedBackup = Join-Path $BackupDir $BackupFile
    if (-not (Test-Path $SelectedBackup)) {
        Write-Error "❌ 指定されたバックアップが見つかりません: $BackupFile"
    }
} else {
    # 対話的選択
    do {
        $choice = Read-Host "復元するバックアップ番号を入力 (1-$($AvailableBackups.Count), デフォルト: 1)"

        if ([string]::IsNullOrWhiteSpace($choice)) {
            $choice = "1"
        }

        if ($choice -match '^\d+$') {
            $idx = [int]$choice
            if ($idx -ge 1 -and $idx -le $AvailableBackups.Count) {
                $SelectedBackup = $AvailableBackups[$idx - 1].FullName
                break
            }
        }

        Write-Host "❌ 1から$($AvailableBackups.Count)の数字を入力してください。" -ForegroundColor Red
    } while ($true)
}

Write-Host ""
Write-Host "選択されたバックアップ: $(Split-Path $SelectedBackup -Leaf)" -ForegroundColor Cyan
Write-Host ""

# 復元確認
Write-Host "⚠️  現在のconfig.jsonを上書きします。続行しますか？ (Y/N)" -ForegroundColor Yellow
$Confirm = Read-Host

if ($Confirm -ne "Y" -and $Confirm -ne "y") {
    Write-Host ""
    Write-Host "復元をキャンセルしました"
    Write-Host ""
    exit 0
}

# 現在のconfig.jsonをバックアップ（復元前の安全措置）
$CurrentBackup = Join-Path $BackupDir "config-before-restore-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
try {
    Copy-Item $ConfigPath $CurrentBackup -Force
    Write-Host "💾 現在の設定をバックアップしました: $(Split-Path $CurrentBackup -Leaf)" -ForegroundColor Green
} catch {
    Write-Warning "現在の設定のバックアップに失敗しましたが続行します: $_"
}

# 復元実行
try {
    Copy-Item $SelectedBackup $ConfigPath -Force
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host "✅ config.jsonを復元しました" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    Write-Host ""
    Write-Host "復元元: $(Split-Path $SelectedBackup -Leaf)"
    Write-Host "復元先: $ConfigPath"
    Write-Host ""
} catch {
    Write-Error "❌ 復元に失敗しました: $_"
}
