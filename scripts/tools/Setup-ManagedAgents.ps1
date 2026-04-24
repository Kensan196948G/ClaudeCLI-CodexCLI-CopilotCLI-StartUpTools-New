<#
.SYNOPSIS
    Anthropic Managed Agents API のセットアップウィザード。
    API キーの設定から Memory Store・Agent Teams の構築まで一括で行う。

.DESCRIPTION
    Step 1: ANTHROPIC_API_KEY を config/managed-agents.json に保存
    Step 2: Memory Store を作成してローカルメモリを移行
    Step 3: 実行環境 (Environment) を作成
    Step 4: 専門エージェント 6 体を作成
    Step 5: CTO オーケストレーターを作成

.EXAMPLE
    .\Setup-ManagedAgents.ps1
    .\Setup-ManagedAgents.ps1 -ApiKey "sk-ant-api03-..." -SkipConfirmation
    .\Setup-ManagedAgents.ps1 -Step memory   # Memory Store のみ
    .\Setup-ManagedAgents.ps1 -Step agents   # エージェントのみ
    .\Setup-ManagedAgents.ps1 -Status        # 現在の状態確認のみ
#>
[CmdletBinding()]
param(
    [string]$ApiKey = "",
    [ValidateSet("all", "memory", "agents", "status")]
    [string]$Step = "all",
    [switch]$SkipConfirmation,
    [switch]$Status
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..") | Select-Object -ExpandProperty Path
$ConfigFile  = Join-Path $ProjectRoot "config\managed-agents.json"
$MemoryPy    = Join-Path $PSScriptRoot "managed-memory.py"
$AgentsPy    = Join-Path $PSScriptRoot "managed-agents-setup.py"
$Python      = "C:\Python314\python.exe"

function Write-Step([string]$msg) { Write-Host "`n[Setup] $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "  ✓ $msg"       -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "  ⚠ $msg"       -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "  ✗ $msg"       -ForegroundColor Red }

function Invoke-PyJson([string]$script, [string[]]$pyArgs) {
    $raw = & $Python $script @pyArgs 2>&1
    # stderr 行を除外して stdout のみ JSON パース
    $stdout = ($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
    if (-not $stdout.Trim()) {
        Write-Warn "Python stdout が空でした: $script $($pyArgs -join ' ')"
        Write-Host "  stderr: $($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | Select-Object -First 3)" -ForegroundColor DarkGray
        return $null
    }
    try { return $stdout | ConvertFrom-Json }
    catch {
        Write-Warn "JSON パース失敗: $($_.Exception.Message)"
        Write-Host "  出力: $($stdout[0..200])" -ForegroundColor DarkGray
        return $null
    }
}

# null-safe プロパティアクセス (Set-StrictMode 対策)
function Get-Prop($obj, [string]$prop, $default = $null) {
    if ($null -eq $obj) { return $default }
    $p = $obj.PSObject.Properties[$prop]
    if ($null -eq $p) { return $default }
    return $p.Value
}

# UTF-8 without BOM で設定ファイルを書き込む (PS 5.1/7 両対応)
function Save-ConfigBomFree([string]$path, [string]$json) {
    $utf8NoBOM = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $json, $utf8NoBOM)
}

# ── Status のみ ───────────────────────────────────────────────────────────────
if ($Status -or $Step -eq "status") {
    Write-Step "現在の状態を確認します"

    $memStatus   = Invoke-PyJson $MemoryPy @("status")
    $agentStatus = Invoke-PyJson $AgentsPy @("status")

    $specCount = 0
    if ($null -ne $agentStatus) {
        $specCount = (Get-Prop $agentStatus 'specialist_agents' @{} | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count
    }
    [PSCustomObject]@{
        api_key_set       = Get-Prop $memStatus "api_key_set"
        api_key_prefix    = Get-Prop $memStatus "api_key_prefix"
        memory_store_id   = Get-Prop $memStatus "store_id"
        remote_memories   = Get-Prop $memStatus "remote_memory_count" 0
        local_files       = Get-Prop $memStatus "local_memory_files" 0
        environment_id    = Get-Prop $agentStatus "environment_id"
        orchestrator_id   = Get-Prop $agentStatus "orchestrator_id"
        specialist_count  = $specCount
        ready_for_session = Get-Prop $agentStatus "ready_for_session"
    } | Format-List
    return
}

# ── API キーの取得・保存 ───────────────────────────────────────────────────────
Write-Step "API キーの設定"

if (-not $ApiKey) {
    $ApiKey = $env:ANTHROPIC_API_KEY
}

if (-not $ApiKey) {
    Write-Warn "ANTHROPIC_API_KEY が環境変数に設定されていません。"
    Write-Host  "  Anthropic API キーを入力してください（console.anthropic.com で取得）:"
    Write-Host  "  形式: sk-ant-api03-..." -ForegroundColor DarkGray
    $ApiKey = Read-Host "  API Key"
}

if ($ApiKey -notmatch "^sk-ant-") {
    Write-Fail "無効な API キー形式です（sk-ant- で始まる必要があります）"
    exit 1
}

# config に保存
$cfg = @{}
if (Test-Path $ConfigFile) {
    $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json -AsHashtable
}
$cfg["apiKey"] = $ApiKey
Save-ConfigBomFree $ConfigFile ($cfg | ConvertTo-Json -Depth 10)
$env:ANTHROPIC_API_KEY = $ApiKey
Write-OK "API キーを $ConfigFile に保存しました。"

# ── Memory Store セットアップ ─────────────────────────────────────────────────
if ($Step -in @("all", "memory")) {
    Write-Step "Memory Store のセットアップ"

    $memStatus = Invoke-PyJson $MemoryPy @("status")
    if ($null -eq $memStatus) { Write-Fail "managed-memory.py status が失敗しました。API キーを確認してください。"; return }

    $storeId = Get-Prop $memStatus "store_id"
    if ($storeId) {
        Write-OK "既存 Memory Store: $storeId"
        Write-OK "リモートメモリ数: $(Get-Prop $memStatus 'remote_memory_count' 0)"
    } else {
        Write-Host "  Memory Store を新規作成します..." -ForegroundColor Gray
        $result = Invoke-PyJson $MemoryPy @("create-store")
        if ($null -ne $result -and (Get-Prop $result "success")) {
            Write-OK "Memory Store 作成: $(Get-Prop $result 'store_id')"
        } else {
            Write-Fail "Memory Store 作成失敗: $(Get-Prop $result 'error' 'unknown')"
        }
    }

    # ローカルメモリのマイグレーション
    $memStatus = Invoke-PyJson $MemoryPy @("status")
    if ($null -ne $memStatus -and (Get-Prop $memStatus "local_memory_files" 0) -gt 0) {
        $migrate = $true
        if (-not $SkipConfirmation) {
            $ans = Read-Host "  ローカルメモリ $($memStatus.local_memory_files) 件をマイグレーションしますか？ (y/n)"
            $migrate = $ans -eq "y"
        }
        if ($migrate) {
            Write-Host "  マイグレーション実行中..." -ForegroundColor Gray
            $result = Invoke-PyJson $MemoryPy @("migrate")
            if ($null -ne $result -and (Get-Prop $result "success")) {
                Write-OK "マイグレーション完了: $(Get-Prop $result 'created' 0) 件作成, $(Get-Prop $result 'skipped' 0) 件スキップ"
            } else {
                Write-Warn "マイグレーション部分失敗: $($result | ConvertTo-Json -Compress)"
            }
        }
    }
}

# ── Agent Teams セットアップ ──────────────────────────────────────────────────
if ($Step -in @("all", "agents")) {
    Write-Step "Agent Teams のセットアップ"

    $agentStatus = Invoke-PyJson $AgentsPy @("status")
    if ($null -eq $agentStatus) { Write-Fail "managed-agents-setup.py status が失敗しました。"; return }

    if (Get-Prop $agentStatus "ready_for_session") {
        Write-OK "エージェント構成済み: Orchestrator=$(Get-Prop $agentStatus 'orchestrator_id')"
        $specCount = (Get-Prop $agentStatus 'specialist_agents' @{} | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count
        Write-OK "専門エージェント: $specCount 体"
    } else {
        $proceed = $true
        if (-not $SkipConfirmation) {
            Write-Host "  以下を作成します:" -ForegroundColor Gray
            Write-Host "    - Environment (実行コンテナ)" -ForegroundColor Gray
            Write-Host "    - Specialist Agents x6 (Architect/Developer/QA/Security/DevOps/Reviewer)" -ForegroundColor Gray
            Write-Host "    - CTO Orchestrator (claude-opus-4-7)" -ForegroundColor Gray
            $ans = Read-Host "  実行しますか？ (y/n)"
            $proceed = $ans -eq "y"
        }

        if ($proceed) {
            Write-Host "  セットアップ実行中（数秒かかります）..." -ForegroundColor Gray
            $result = Invoke-PyJson $AgentsPy @("setup-all")
            if ($null -ne $result -and (Get-Prop $result "setup_complete")) {
                Write-OK "Environment: $(Get-Prop $result 'environment_id')"
                Write-OK "Orchestrator: $(Get-Prop $result 'orchestrator_id')"
                Write-OK "Specialist Agents: $(Get-Prop $result 'specialist_count') 体"
                Write-OK "次のステップ: $(Get-Prop $result 'next_step')"
            } else {
                Write-Fail "セットアップ失敗: $($result | ConvertTo-Json -Compress)"
            }
        }
    }
}

# ── 最終サマリー ──────────────────────────────────────────────────────────────
Write-Step "セットアップ完了"
$finalStatus = Invoke-PyJson $AgentsPy @("status")
if ($null -ne $finalStatus) {
    $specCount = (Get-Prop $finalStatus 'specialist_agents' @{} | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count
    [PSCustomObject]@{
        ready_for_session = Get-Prop $finalStatus "ready_for_session"
        orchestrator_id   = Get-Prop $finalStatus "orchestrator_id"
        specialist_agents = $specCount
        config_file       = $ConfigFile
        usage_example     = "python scripts\tools\managed-session.py run --phase monitor"
    } | Format-List
}

if (Get-Prop $finalStatus "ready_for_session") {
    Write-Host "`n  セッションを開始するには:" -ForegroundColor Green
    Write-Host "  python scripts\tools\managed-session.py run --phase monitor" -ForegroundColor White
} else {
    Write-Warn "セットアップが不完全です。エラーを確認してください。"
}
