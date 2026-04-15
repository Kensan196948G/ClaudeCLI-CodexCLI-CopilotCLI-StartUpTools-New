# ============================================================
# MessageBus.psm1 - Agent Message Bus (Phase 1)
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v3.1.0
# Issue #127 — state.json 拡張による非同期メッセージ交換
#
# Phase 1 対象トピック:
#   - phase.transition  : フェーズ切替通知 (Orchestrator → 全 Agent)
#   - ci.status         : CI 結果通知 (DevOps → Orchestrator, QA)
# ============================================================

Set-StrictMode -Version Latest

# --- 定数 ---
$script:DefaultStatePath = 'state.json'
$script:MaxMessagesPerTopic = 10

# Phase 1 で許可するトピック一覧
$script:AllowedTopics = @(
    'phase.transition',
    'ci.status'
)

# --- 内部ヘルパー ---

function Get-StateFilePath {
    param([string]$RepoRoot)
    if (-not $RepoRoot) {
        $root = git rev-parse --show-toplevel 2>$null
        $RepoRoot = if ($root) { $root } else { '.' }
    }
    return Join-Path $RepoRoot $script:DefaultStatePath
}

function Read-StateJson {
    param([string]$StatePath)
    if (-not (Test-Path $StatePath)) {
        throw "state.json が見つかりません: $StatePath"
    }
    $raw = Get-Content -Path $StatePath -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

function Write-StateJson {
    param(
        [string]$StatePath,
        [psobject]$State
    )
    $json = $State | ConvertTo-Json -Depth 10 -Compress:$false
    Set-Content -Path $StatePath -Value $json -Encoding UTF8 -NoNewline
}

function New-BusSection {
    <#
    .SYNOPSIS
        message_bus セクションの初期値を返す。
    #>
    $bus = [ordered]@{}
    foreach ($topic in $script:AllowedTopics) {
        $bus[$topic] = @()
    }
    return [pscustomobject]$bus
}

function Assert-TopicAllowed {
    param([string]$Topic)
    if ($Topic -notin $script:AllowedTopics) {
        throw "未対応トピック '$Topic'。Phase 1 で利用可能なトピック: $($script:AllowedTopics -join ', ')"
    }
}

function New-MessageId {
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $random    = -join ((65..90) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
    return "msg-$timestamp-$random"
}

# --- 公開関数 ---

function Publish-BusMessage {
    <#
    .SYNOPSIS
        指定トピックにメッセージを publish する。

    .DESCRIPTION
        state.json の message_bus セクションに新しいメッセージを追加する。
        各トピックの最大保持件数 (MaxMessagesPerTopic = 10) を超えた場合、
        最古のメッセージを自動的に削除する。

    .PARAMETER Topic
        メッセージを publish するトピック名。
        Phase 1 では 'phase.transition' または 'ci.status' のみ有効。

    .PARAMETER Publisher
        メッセージを送信する Agent 名 (例: "Orchestrator", "DevOps")。

    .PARAMETER Payload
        メッセージ本文。ハッシュテーブルまたは psobject で指定する。

    .PARAMETER StatePath
        state.json のパス。省略時は自動検出。

    .OUTPUTS
        発行したメッセージの ID 文字列を返す。

    .EXAMPLE
        Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
            -Payload @{ from = 'Monitor'; to = 'Development' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Topic,

        [Parameter(Mandatory = $true)]
        [string]$Publisher,

        [Parameter(Mandatory = $true)]
        [psobject]$Payload,

        [Parameter(Mandatory = $false)]
        [string]$StatePath
    )

    Assert-TopicAllowed -Topic $Topic

    if (-not $StatePath) { $StatePath = Get-StateFilePath }

    $state = Read-StateJson -StatePath $StatePath

    # message_bus セクションが存在しない場合は初期化
    if (-not ($state.PSObject.Properties.Name -contains 'message_bus') -or
        $null -eq $state.message_bus) {
        $state | Add-Member -MemberType NoteProperty -Name 'message_bus' -Value (New-BusSection) -Force
    }

    $bus = $state.message_bus

    # トピックキューが存在しない場合は初期化
    if (-not ($bus.PSObject.Properties.Name -contains $Topic)) {
        $bus | Add-Member -MemberType NoteProperty -Name $Topic -Value @() -Force
    }

    $msgId = New-MessageId

    $newMessage = [pscustomobject]@{
        id          = $msgId
        timestamp   = (Get-Date -Format 'o')
        publisher   = $Publisher
        payload     = $Payload
        consumed_by = @()
    }

    # 既存キューを配列として取得
    $queue = @($bus.$Topic)
    $queue += $newMessage

    # 最大件数超過時に古いメッセージを削除
    if ($queue.Count -gt $script:MaxMessagesPerTopic) {
        $queue = $queue | Select-Object -Last $script:MaxMessagesPerTopic
    }

    $bus | Add-Member -MemberType NoteProperty -Name $Topic -Value $queue -Force

    Write-StateJson -StatePath $StatePath -State $state

    Write-Verbose "MessageBus: Published [$Topic] id=$msgId publisher=$Publisher"
    return $msgId
}

function Get-BusMessages {
    <#
    .SYNOPSIS
        指定トピックのメッセージ一覧を取得する。

    .DESCRIPTION
        state.json の message_bus セクションから指定トピックのメッセージを返す。
        Consumer 名を指定した場合、そのエージェントがまだ consume していない
        メッセージのみを返す (未読フィルタ)。

    .PARAMETER Topic
        取得するトピック名。

    .PARAMETER Consumer
        フィルタするエージェント名。省略時は全メッセージを返す。

    .PARAMETER StatePath
        state.json のパス。省略時は自動検出。

    .OUTPUTS
        メッセージオブジェクトの配列を返す。

    .EXAMPLE
        # Orchestrator が未読の phase.transition を取得
        Get-BusMessages -Topic 'phase.transition' -Consumer 'Orchestrator'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Topic,

        [Parameter(Mandatory = $false)]
        [string]$Consumer,

        [Parameter(Mandatory = $false)]
        [string]$StatePath
    )

    Assert-TopicAllowed -Topic $Topic

    if (-not $StatePath) { $StatePath = Get-StateFilePath }

    if (-not (Test-Path $StatePath)) {
        return @()
    }

    $state = Read-StateJson -StatePath $StatePath

    if (-not ($state.PSObject.Properties.Name -contains 'message_bus') -or
        $null -eq $state.message_bus) {
        return @()
    }

    $bus = $state.message_bus

    if (-not ($bus.PSObject.Properties.Name -contains $Topic)) {
        return @()
    }

    $messages = @($bus.$Topic)

    if ($Consumer) {
        $messages = $messages | Where-Object {
            $consumed = @($_.consumed_by)
            $Consumer -notin $consumed
        }
    }

    return $messages
}

function Confirm-BusMessage {
    <#
    .SYNOPSIS
        指定メッセージを Consumer として consume 済みにマークする。

    .DESCRIPTION
        state.json の当該メッセージの consumed_by 配列に Consumer 名を追加する。
        既に consume 済みの場合は何もしない (冪等)。
        全 Subscriber が consume 済みになったメッセージはそのまま保持される
        (GC は Phase 2 で実装)。

    .PARAMETER Topic
        メッセージが属するトピック名。

    .PARAMETER MessageId
        consume する対象のメッセージ ID。

    .PARAMETER Consumer
        consume する Agent 名。

    .PARAMETER StatePath
        state.json のパス。省略時は自動検出。

    .OUTPUTS
        成功した場合は $true、メッセージが見つからない場合は $false を返す。

    .EXAMPLE
        Confirm-BusMessage -Topic 'ci.status' -MessageId 'msg-20260415123456-AbCd' `
            -Consumer 'Orchestrator'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Topic,

        [Parameter(Mandatory = $true)]
        [string]$MessageId,

        [Parameter(Mandatory = $true)]
        [string]$Consumer,

        [Parameter(Mandatory = $false)]
        [string]$StatePath
    )

    Assert-TopicAllowed -Topic $Topic

    if (-not $StatePath) { $StatePath = Get-StateFilePath }

    $state = Read-StateJson -StatePath $StatePath

    if (-not ($state.PSObject.Properties.Name -contains 'message_bus') -or
        $null -eq $state.message_bus) {
        return $false
    }

    $bus = $state.message_bus

    if (-not ($bus.PSObject.Properties.Name -contains $Topic)) {
        return $false
    }

    $found = $false
    $updatedQueue = @($bus.$Topic) | ForEach-Object {
        if ($_.id -eq $MessageId) {
            $found = $true
            $consumed = @($_.consumed_by)
            if ($Consumer -notin $consumed) {
                $consumed += $Consumer
                $_ | Add-Member -MemberType NoteProperty -Name 'consumed_by' -Value $consumed -Force
            }
        }
        $_
    }

    if (-not $found) {
        Write-Verbose "MessageBus: Message '$MessageId' not found in topic '$Topic'"
        return $false
    }

    $bus | Add-Member -MemberType NoteProperty -Name $Topic -Value $updatedQueue -Force

    Write-StateJson -StatePath $StatePath -State $state

    Write-Verbose "MessageBus: Confirmed [$Topic] id=$MessageId consumer=$Consumer"
    return $true
}

function Get-BusStatus {
    <#
    .SYNOPSIS
        Message Bus の現在状態サマリーを返す。

    .DESCRIPTION
        各トピックのメッセージ件数・未読件数を集計して表示する。
        デバッグ・監視用途。

    .PARAMETER StatePath
        state.json のパス。省略時は自動検出。

    .OUTPUTS
        トピックごとのサマリーオブジェクト配列を返す。

    .EXAMPLE
        Get-BusStatus | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StatePath
    )

    if (-not $StatePath) { $StatePath = Get-StateFilePath }

    if (-not (Test-Path $StatePath)) {
        Write-Warning "state.json が見つかりません: $StatePath"
        return @()
    }

    $state = Read-StateJson -StatePath $StatePath

    $results = foreach ($topic in $script:AllowedTopics) {
        $count    = 0
        $consumed = 0

        if (($state.PSObject.Properties.Name -contains 'message_bus') -and
            $null -ne $state.message_bus -and
            ($state.message_bus.PSObject.Properties.Name -contains $topic)) {

            $msgs  = @($state.message_bus.$topic)
            $count = $msgs.Count
            $consumed = @($msgs | Where-Object { @($_.consumed_by).Count -gt 0 }).Count
        }

        [pscustomobject]@{
            Topic        = $topic
            TotalMessages = $count
            ConsumedCount = $consumed
            PendingCount  = $count - $consumed
        }
    }

    return $results
}

function Initialize-MessageBus {
    <#
    .SYNOPSIS
        state.json に message_bus セクションを初期化する。

    .DESCRIPTION
        既に message_bus セクションが存在する場合は何もしない (冪等)。
        state.json が存在しない場合はエラーを返す。

    .PARAMETER StatePath
        state.json のパス。省略時は自動検出。

    .OUTPUTS
        初期化された場合は $true、既存のため skip した場合は $false を返す。

    .EXAMPLE
        Initialize-MessageBus
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StatePath
    )

    if (-not $StatePath) { $StatePath = Get-StateFilePath }

    $state = Read-StateJson -StatePath $StatePath

    if (($state.PSObject.Properties.Name -contains 'message_bus') -and
        $null -ne $state.message_bus) {
        Write-Verbose "MessageBus: message_bus セクションは既に存在します (skip)"
        return $false
    }

    $state | Add-Member -MemberType NoteProperty -Name 'message_bus' -Value (New-BusSection) -Force

    Write-StateJson -StatePath $StatePath -State $state

    Write-Verbose "MessageBus: message_bus セクションを初期化しました"
    return $true
}

Export-ModuleMember -Function @(
    'Publish-BusMessage',
    'Get-BusMessages',
    'Confirm-BusMessage',
    'Get-BusStatus',
    'Initialize-MessageBus'
)
