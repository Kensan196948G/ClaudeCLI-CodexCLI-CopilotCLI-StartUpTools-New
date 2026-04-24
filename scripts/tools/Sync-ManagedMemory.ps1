<#
.SYNOPSIS
    Managed Agents Memory Store とローカルメモリファイルを同期する。

.DESCRIPTION
    push: ローカル ~/.claude/.../memory/*.md → Memory Store (デフォルト)
    pull: Memory Store → ローカル (他端末からの取得)
    list: ストア内のメモリ一覧を表示
    write: 1件のメモリを書き込む

.EXAMPLE
    .\Sync-ManagedMemory.ps1               # push (ローカル → リモート)
    .\Sync-ManagedMemory.ps1 -Direction pull
    .\Sync-ManagedMemory.ps1 -List
    .\Sync-ManagedMemory.ps1 -Write -Path /feedback/test.md -Content "内容"
#>
[CmdletBinding()]
param(
    [ValidateSet("push", "pull")]
    [string]$Direction = "push",
    [switch]$List,
    [switch]$Write,
    [string]$Path = "",
    [string]$Content = "",
    [string]$StoreId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$MemoryPy = Join-Path $PSScriptRoot "managed-memory.py"
$Python   = "C:\Python314\python.exe"

function Write-Step([string]$msg) { Write-Host "[Memory] $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Fail([string]$msg) { Write-Host "  ✗ $msg" -ForegroundColor Red }

function Invoke-PyJson([string]$script, [string[]]$cmdArgs) {
    $out = & $Python $script @cmdArgs 2>$null
    try { return $out | ConvertFrom-Json }
    catch { return $null }
}

# ── List ──────────────────────────────────────────────────────────────────────
if ($List) {
    Write-Step "Memory Store 一覧"
    $pyArgs = @("list")
    if ($StoreId) { $pyArgs += "--store-id", $StoreId }
    $result = Invoke-PyJson $MemoryPy $pyArgs
    if ($result.count -eq 0) {
        Write-Host "  (メモリなし)" -ForegroundColor Gray
    } else {
        Write-Host "  ストア: $($result.store_id)" -ForegroundColor Gray
        foreach ($mem in $result.memories) {
            Write-Host "  [$($mem.type)] $($mem.path)" -ForegroundColor White
        }
        Write-OK "合計: $($result.count) 件"
    }
    return
}

# ── Write ─────────────────────────────────────────────────────────────────────
if ($Write) {
    if (-not $Path) {
        Write-Fail "--Path が必要です（例: /feedback/foo.md）"
        exit 1
    }
    $pyArgs = @("write", "--path", $Path)
    if ($StoreId) { $pyArgs += "--store-id", $StoreId }
    if ($Content) {
        $pyArgs += "--content", $Content
        $result = Invoke-PyJson $MemoryPy $pyArgs
    } else {
        # stdin から読む
        $result = $Content | & $Python $MemoryPy @pyArgs 2>$null | ConvertFrom-Json
    }
    if ($result.action) {
        Write-OK "$($result.action.ToUpper()): $($result.path) (id=$($result.id))"
    } else {
        Write-Fail "書き込み失敗: $($result | ConvertTo-Json -Compress)"
    }
    return
}

# ── Sync (push / pull) ────────────────────────────────────────────────────────
Write-Step "同期 ($Direction)"

$pyArgs = @("sync", "--direction", $Direction)
if ($StoreId) { $pyArgs += "--store-id", $StoreId }

$result = Invoke-PyJson $MemoryPy $pyArgs

if ($Direction -eq "push" -and $result.success) {
    Write-OK "Push 完了: $($result.created) 件作成, $($result.skipped) 件スキップ"
    if ($result.results) {
        foreach ($r in $result.results) {
            $icon = switch ($r.status) {
                "created"        { "+" }
                "skipped_exists" { "=" }
                "error"          { "!" }
                default          { "?" }
            }
            Write-Host "  [$icon] $($r.path)" -ForegroundColor $(
                if ($r.status -eq "error") { "Red" } else { "Gray" }
            )
        }
    }
} elseif ($Direction -eq "pull" -and $result.direction -eq "pull") {
    Write-OK "Pull 完了: $($result.count) 件取得"
    foreach ($r in $result.pulled) {
        Write-Host "  ← $($r.path)" -ForegroundColor Gray
    }
} else {
    Write-Fail "同期失敗: $($result | ConvertTo-Json -Compress)"
}
