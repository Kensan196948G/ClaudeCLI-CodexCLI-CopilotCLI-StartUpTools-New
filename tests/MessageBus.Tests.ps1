# ============================================================
# MessageBus.Tests.ps1 - MessageBus.psm1 のユニットテスト
# Pester 5.x
# Issue #127 — Message Bus Phase 1
# ============================================================

BeforeAll {
    $script:RepoRoot  = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\lib\MessageBus.psm1'
    Import-Module $script:ModulePath -Force

    # --- ヘルパー: テスト用 state.json を TestDrive に作成 ---
    function script:New-TestStateJson {
        param([string]$Path, [hashtable]$ExtraProps = @{})
        $state = [ordered]@{
            goal      = @{ title = 'Test' }
            execution = @{ phase = 'Monitor' }
        }
        foreach ($key in $ExtraProps.Keys) { $state[$key] = $ExtraProps[$key] }
        $json = $state | ConvertTo-Json -Depth 10
        Set-Content -Path $Path -Value $json -Encoding UTF8
    }
}

Describe 'Initialize-MessageBus' {

    Context 'message_bus セクションが存在しない場合' {

        BeforeEach {
            $script:StatePath = Join-Path $TestDrive 'state.json'
            New-TestStateJson -Path $script:StatePath
        }

        It 'message_bus セクションを追加して $true を返す' {
            $result = Initialize-MessageBus -StatePath $script:StatePath
            $result | Should -Be $true
        }

        It '追加後の state.json に message_bus セクションが存在する' {
            Initialize-MessageBus -StatePath $script:StatePath | Out-Null
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            $state.PSObject.Properties.Name | Should -Contain 'message_bus'
        }

        It 'phase.transition トピックが空配列で初期化される' {
            Initialize-MessageBus -StatePath $script:StatePath | Out-Null
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            @($state.message_bus.'phase.transition') | Should -HaveCount 0
        }

        It 'ci.status トピックが空配列で初期化される' {
            Initialize-MessageBus -StatePath $script:StatePath | Out-Null
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            @($state.message_bus.'ci.status') | Should -HaveCount 0
        }
    }

    Context 'message_bus セクションが既に存在する場合' {

        BeforeEach {
            $script:StatePath = Join-Path $TestDrive 'state.json'
            $existingBus = @{ 'phase.transition' = @(); 'ci.status' = @() }
            New-TestStateJson -Path $script:StatePath -ExtraProps @{ message_bus = $existingBus }
        }

        It '$false を返す (冪等)' {
            $result = Initialize-MessageBus -StatePath $script:StatePath
            $result | Should -Be $false
        }
    }
}

Describe 'Publish-BusMessage' {

    BeforeEach {
        $script:StatePath = Join-Path $TestDrive 'state.json'
        New-TestStateJson -Path $script:StatePath
        Initialize-MessageBus -StatePath $script:StatePath | Out-Null
    }

    Context '正常系: phase.transition トピック' {

        It 'メッセージ ID を返す' {
            $id = Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
                -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath
            $id | Should -Not -BeNullOrEmpty
            $id | Should -Match '^msg-'
        }

        It 'state.json にメッセージが保存される' {
            Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
                -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath | Out-Null
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            @($state.message_bus.'phase.transition') | Should -HaveCount 1
        }

        It 'publisher フィールドが正しく保存される' {
            Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
                -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath | Out-Null
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            $msg = @($state.message_bus.'phase.transition')[0]
            $msg.publisher | Should -Be 'Orchestrator'
        }

        It 'consumed_by が空配列で初期化される' {
            Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
                -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath | Out-Null
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            $msg = @($state.message_bus.'phase.transition')[0]
            @($msg.consumed_by) | Should -HaveCount 0
        }

        It 'timestamp が ISO8601 形式で保存される' {
            Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
                -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath | Out-Null
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            $msg = @($state.message_bus.'phase.transition')[0]
            # ConvertFrom-Json が ISO8601 文字列を DateTime 型に自動変換するため ToString('o') で戻す
            $tsStr = if ($msg.timestamp -is [DateTime]) { $msg.timestamp.ToString('o') } else { [string]$msg.timestamp }
            $tsStr | Should -Match '^\d{4}-\d{2}-\d{2}T'
        }
    }

    Context '正常系: ci.status トピック' {

        It 'ci.status にメッセージを publish できる' {
            Publish-BusMessage -Topic 'ci.status' -Publisher 'DevOps' `
                -Payload @{ status = 'pass'; run_id = '99999' } -StatePath $script:StatePath | Out-Null
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            @($state.message_bus.'ci.status') | Should -HaveCount 1
        }
    }

    Context '上限制御: MaxMessagesPerTopic = 10' {

        It '11件 publish すると最新 10 件のみ保持される' {
            for ($i = 1; $i -le 11; $i++) {
                Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
                    -Payload @{ seq = $i } -StatePath $script:StatePath | Out-Null
            }
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            @($state.message_bus.'phase.transition') | Should -HaveCount 10
        }

        It '11件 publish 後、保持されるのは seq 2〜11 のメッセージ' {
            for ($i = 1; $i -le 11; $i++) {
                Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
                    -Payload @{ seq = $i } -StatePath $script:StatePath | Out-Null
            }
            $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
            $msgs = @($state.message_bus.'phase.transition')
            $msgs[0].payload.seq | Should -Be 2
            $msgs[-1].payload.seq | Should -Be 11
        }
    }

    Context '異常系: 未対応トピック' {

        It '未対応トピックを指定するとエラーになる' {
            { Publish-BusMessage -Topic 'unknown.topic' -Publisher 'Orchestrator' `
                -Payload @{} -StatePath $script:StatePath } | Should -Throw
        }
    }
}

Describe 'Get-BusMessage' {

    BeforeEach {
        $script:StatePath = Join-Path $TestDrive 'state.json'
        New-TestStateJson -Path $script:StatePath
        Initialize-MessageBus -StatePath $script:StatePath | Out-Null
    }

    Context 'Consumer 未指定 (全件取得)' {

        It 'publish した件数分だけ返す' {
            Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
                -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath | Out-Null
            Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
                -Payload @{ from = 'Development'; to = 'Verify' } -StatePath $script:StatePath | Out-Null
            $msgs = Get-BusMessage -Topic 'phase.transition' -StatePath $script:StatePath
            @($msgs) | Should -HaveCount 2
        }

        It 'メッセージがない場合は空を返す' {
            $msgs = Get-BusMessage -Topic 'ci.status' -StatePath $script:StatePath
            @($msgs) | Should -HaveCount 0
        }
    }

    Context 'Consumer 指定 (未読フィルタ)' {

        It 'consume 前は未読として返る' {
            Publish-BusMessage -Topic 'ci.status' -Publisher 'DevOps' `
                -Payload @{ status = 'pass' } -StatePath $script:StatePath | Out-Null
            $msgs = Get-BusMessage -Topic 'ci.status' -Consumer 'Orchestrator' -StatePath $script:StatePath
            @($msgs) | Should -HaveCount 1
        }

        It 'Confirm-BusMessage 後は既読として除外される' {
            $id = Publish-BusMessage -Topic 'ci.status' -Publisher 'DevOps' `
                -Payload @{ status = 'pass' } -StatePath $script:StatePath
            Confirm-BusMessage -Topic 'ci.status' -MessageId $id -Consumer 'Orchestrator' `
                -StatePath $script:StatePath | Out-Null
            $msgs = Get-BusMessage -Topic 'ci.status' -Consumer 'Orchestrator' -StatePath $script:StatePath
            @($msgs) | Should -HaveCount 0
        }

        It '別の Consumer には既読にならない' {
            $id = Publish-BusMessage -Topic 'ci.status' -Publisher 'DevOps' `
                -Payload @{ status = 'pass' } -StatePath $script:StatePath
            Confirm-BusMessage -Topic 'ci.status' -MessageId $id -Consumer 'Orchestrator' `
                -StatePath $script:StatePath | Out-Null
            $msgs = Get-BusMessage -Topic 'ci.status' -Consumer 'QA' -StatePath $script:StatePath
            @($msgs) | Should -HaveCount 1
        }
    }

    Context 'state.json が存在しない場合' {

        It '空配列を返す' {
            $msgs = Get-BusMessage -Topic 'phase.transition' `
                -StatePath (Join-Path $TestDrive 'nonexistent.json')
            @($msgs) | Should -HaveCount 0
        }
    }
}

Describe 'Confirm-BusMessage' {

    BeforeEach {
        $script:StatePath = Join-Path $TestDrive 'state.json'
        New-TestStateJson -Path $script:StatePath
        Initialize-MessageBus -StatePath $script:StatePath | Out-Null
    }

    It '存在するメッセージを consume すると $true を返す' {
        $id = Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
            -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath
        $result = Confirm-BusMessage -Topic 'phase.transition' -MessageId $id `
            -Consumer 'Developer' -StatePath $script:StatePath
        $result | Should -Be $true
    }

    It 'consumed_by に Consumer 名が追加される' {
        $id = Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
            -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath
        Confirm-BusMessage -Topic 'phase.transition' -MessageId $id `
            -Consumer 'Developer' -StatePath $script:StatePath | Out-Null
        $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
        $msg = @($state.message_bus.'phase.transition') | Where-Object { $_.id -eq $id }
        @($msg.consumed_by) | Should -Contain 'Developer'
    }

    It '同じ Consumer で 2 回 Confirm しても冪等 (重複追加なし)' {
        $id = Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
            -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath
        Confirm-BusMessage -Topic 'phase.transition' -MessageId $id `
            -Consumer 'Developer' -StatePath $script:StatePath | Out-Null
        Confirm-BusMessage -Topic 'phase.transition' -MessageId $id `
            -Consumer 'Developer' -StatePath $script:StatePath | Out-Null
        $state = Get-Content $script:StatePath -Raw | ConvertFrom-Json
        $msg = @($state.message_bus.'phase.transition') | Where-Object { $_.id -eq $id }
        @($msg.consumed_by) | Where-Object { $_ -eq 'Developer' } | Should -HaveCount 1
    }

    It '存在しないメッセージ ID を指定すると $false を返す' {
        Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
            -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath | Out-Null
        $result = Confirm-BusMessage -Topic 'phase.transition' -MessageId 'msg-nonexistent' `
            -Consumer 'Developer' -StatePath $script:StatePath
        $result | Should -Be $false
    }
}

Describe 'Get-BusStatus' {

    BeforeEach {
        $script:StatePath = Join-Path $TestDrive 'state.json'
        New-TestStateJson -Path $script:StatePath
        Initialize-MessageBus -StatePath $script:StatePath | Out-Null
    }

    It '2 トピック分のサマリーを返す' {
        $status = Get-BusStatus -StatePath $script:StatePath
        @($status) | Should -HaveCount 2
    }

    It 'TotalMessages が publish 件数と一致する' {
        Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
            -Payload @{ from = 'Monitor'; to = 'Development' } -StatePath $script:StatePath | Out-Null
        Publish-BusMessage -Topic 'phase.transition' -Publisher 'Orchestrator' `
            -Payload @{ from = 'Development'; to = 'Verify' } -StatePath $script:StatePath | Out-Null
        $status = Get-BusStatus -StatePath $script:StatePath
        $row = $status | Where-Object { $_.Topic -eq 'phase.transition' }
        $row.TotalMessages | Should -Be 2
    }

    It 'ConsumedCount が Confirm 済み件数と一致する' {
        $id = Publish-BusMessage -Topic 'ci.status' -Publisher 'DevOps' `
            -Payload @{ status = 'pass' } -StatePath $script:StatePath
        Confirm-BusMessage -Topic 'ci.status' -MessageId $id `
            -Consumer 'Orchestrator' -StatePath $script:StatePath | Out-Null
        $status = Get-BusStatus -StatePath $script:StatePath
        $row = $status | Where-Object { $_.Topic -eq 'ci.status' }
        $row.ConsumedCount | Should -Be 1
    }

    It 'PendingCount = TotalMessages - ConsumedCount' {
        $id = Publish-BusMessage -Topic 'ci.status' -Publisher 'DevOps' `
            -Payload @{ status = 'pass' } -StatePath $script:StatePath
        Publish-BusMessage -Topic 'ci.status' -Publisher 'DevOps' `
            -Payload @{ status = 'fail' } -StatePath $script:StatePath | Out-Null
        Confirm-BusMessage -Topic 'ci.status' -MessageId $id `
            -Consumer 'Orchestrator' -StatePath $script:StatePath | Out-Null
        $status = Get-BusStatus -StatePath $script:StatePath
        $row = $status | Where-Object { $_.Topic -eq 'ci.status' }
        $row.PendingCount | Should -Be 1
    }
}
