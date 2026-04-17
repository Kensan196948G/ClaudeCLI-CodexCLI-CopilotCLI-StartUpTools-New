# ============================================================
# AgentTeams.Tests.ps1 - AgentTeams.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $script:RepoRoot 'scripts\lib\AgentTeams.psm1') -Force
}

Describe 'Import-AgentDefinitions' {

    Context 'agents ディレクトリが存在する場合' {

        BeforeAll {
            $script:AgentsDir = Join-Path $TestDrive 'agents'
            New-Item -ItemType Directory -Path $script:AgentsDir -Force | Out-Null

            $frontmatterAgent = @"
---
name: test-architect
description: Test architecture agent
tools: Read, Write, Edit
---

# Test Architect

Designs systems.
"@
            Set-Content -Path (Join-Path $script:AgentsDir 'test-architect.md') -Value $frontmatterAgent -Encoding UTF8

            $simplAgent = @"
# Simple Agent

Handles simple tasks.
"@
            Set-Content -Path (Join-Path $script:AgentsDir 'simple-agent.md') -Value $simplAgent -Encoding UTF8

            Set-Content -Path (Join-Path $script:AgentsDir 'CLAUDE.md') -Value '# skip' -Encoding UTF8
        }

        It 'Agent 定義ファイルを読み込めること' {
            $result = Import-AgentDefinitions -AgentsDir $script:AgentsDir
            @($result).Count | Should -Be 2
        }

        It 'frontmatter の name を正しくパースすること' {
            $result = Import-AgentDefinitions -AgentsDir $script:AgentsDir
            $architect = @($result) | Where-Object { $_.id -eq 'test-architect' }
            $architect.name | Should -Be 'test-architect'
        }

        It 'frontmatter の description を正しくパースすること' {
            $result = Import-AgentDefinitions -AgentsDir $script:AgentsDir
            $architect = @($result) | Where-Object { $_.id -eq 'test-architect' }
            $architect.description | Should -Be 'Test architecture agent'
        }

        It 'frontmatter の tools を配列としてパースすること' {
            $result = Import-AgentDefinitions -AgentsDir $script:AgentsDir
            $architect = @($result) | Where-Object { $_.id -eq 'test-architect' }
            $architect.tools.Count | Should -Be 3
            $architect.tools[0] | Should -Be 'Read'
        }

        It 'frontmatter がない場合は本文から description を抽出すること' {
            $result = Import-AgentDefinitions -AgentsDir $script:AgentsDir
            $simple = @($result) | Where-Object { $_.id -eq 'simple-agent' }
            $simple.description | Should -Be 'Handles simple tasks.'
        }

        It 'CLAUDE.md をスキップすること' {
            $result = Import-AgentDefinitions -AgentsDir $script:AgentsDir
            $claude = @($result) | Where-Object { $_.id -eq 'CLAUDE' }
            $claude | Should -BeNullOrEmpty
        }
    }

    Context 'agents ディレクトリが存在しない場合' {
        It '空配列を返すこと' {
            $result = Import-AgentDefinitions -AgentsDir (Join-Path $TestDrive 'nonexistent')
            @($result).Count | Should -Be 0
        }
    }

    Context '実際の claudeos agents を読み込む場合' {
        It '15 個以上の Agent を読み込めること' {
            # 棚卸し 2026Q2 (Issue #117-#120) でカテゴリ A+D 計 55 件を削除。残存 17 件以上を確認。
            $agentsDir = Join-Path $script:RepoRoot '.claude\claudeos\agents'
            if (Test-Path $agentsDir) {
                $result = Import-AgentDefinitions -AgentsDir $agentsDir
                @($result).Count | Should -BeGreaterOrEqual 15
            }
        }
    }
}

Describe 'Get-TaskTypeAnalysis' {

    Context 'API 関連タスクの場合' {
        It 'api タイプが含まれること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Create REST API endpoint'
            $result.types | Should -Contain 'api'
        }

        It 'dev-api が推薦されること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Build REST API'
            $result.agents | Should -Contain 'dev-api'
        }
    }

    Context 'セキュリティ関連タスクの場合' {
        It 'security タイプが含まれること' {
            $result = Get-TaskTypeAnalysis -TaskDescription '認証モジュールのセキュリティレビュー'
            $result.types | Should -Contain 'security'
        }
    }

    Context 'CI 関連タスクの場合' {
        It 'ci タイプが含まれること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Fix CI pipeline build failure'
            $result.types | Should -Contain 'ci'
        }

        It 'build-error-resolver が推薦されること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'CI build fails'
            $result.agents | Should -Contain 'build-error-resolver'
        }
    }

    Context '複数タイプが該当する場合' {
        It '複数タイプが返されること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'API endpoint with database migration and security audit'
            $result.types.Count | Should -BeGreaterOrEqual 3
        }

        It 'エージェントが重複なしで返されること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'security authentication security review'
            $uniqueCount = ($result.agents | Select-Object -Unique).Count
            $uniqueCount | Should -Be $result.agents.Count
        }
    }

    Context 'マッチしないタスクの場合' {
        It 'general タイプが返されること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'do something completely unrelated xyz'
            $result.types | Should -Contain 'general'
        }
    }

    Context '言語別マッチの場合' {
        It 'TypeScript タスクが検出されること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Fix TypeScript type errors'
            $result.types | Should -Contain 'typescript'
            $result.agents | Should -Contain 'typescript-reviewer'
        }

        It 'Python タスクが検出されること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Django model migration'
            $result.types | Should -Contain 'python'
        }

        It 'Rust タスクが検出されること' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Update Cargo.toml dependencies'
            $result.types | Should -Contain 'rust'
        }
    }
}

Describe 'Get-BacklogRuleMatch' {

    Context '有効な rules ファイルの場合' {

        BeforeAll {
            $script:RulesPath = Join-Path $TestDrive 'rules.json'
            $rules = @{
                default = @{ priority = 'P3'; owner = 'Default'; source = 'Test' }
                rules   = @(
                    @{ pattern = 'MCP|memory';         priority = 'P1'; owner = 'Ops' }
                    @{ pattern = 'Agent Teams';         priority = 'P1'; owner = 'Architect' }
                    @{ pattern = 'docs|README';         priority = 'P2'; owner = 'ScrumMaster' }
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $script:RulesPath -Value $rules -Encoding UTF8
        }

        It 'MCP タスクに P1/Ops が割り当てられること' {
            $result = Get-BacklogRuleMatch -TaskDescription 'MCP server health check' -RulesPath $script:RulesPath
            $result.priority | Should -Be 'P1'
            $result.owner | Should -Be 'Ops'
            $result.matched | Should -Be $true
        }

        It 'Agent Teams タスクに P1/Architect が割り当てられること' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Agent Teams runtime implementation' -RulesPath $script:RulesPath
            $result.priority | Should -Be 'P1'
            $result.owner | Should -Be 'Architect'
        }

        It 'マッチしないタスクにデフォルトが適用されること' {
            $result = Get-BacklogRuleMatch -TaskDescription 'random task xyz' -RulesPath $script:RulesPath
            $result.priority | Should -Be 'P3'
            $result.owner | Should -Be 'Default'
            $result.matched | Should -Be $false
        }
    }

    Context 'rules ファイルが存在しない場合' {
        It 'デフォルト値を返すこと' {
            $result = Get-BacklogRuleMatch -TaskDescription 'test' -RulesPath (Join-Path $TestDrive 'nonexistent.json')
            $result.priority | Should -Be 'P2'
            $result.owner | Should -Be 'ScrumMaster'
        }
    }
}

Describe 'New-AgentTeam' {

    BeforeAll {
        $script:AgentsDir = Join-Path $TestDrive 'team-agents'
        New-Item -ItemType Directory -Path $script:AgentsDir -Force | Out-Null

        foreach ($name in @('architect', 'planner', 'loop-operator', 'qa', 'security', 'ops', 'code-reviewer', 'api-designer', 'dev-api', 'tester', 'database-reviewer')) {
            $content = "---`nname: $name`ndescription: $name agent for testing`ntools: Read`n---`n# $name"
            Set-Content -Path (Join-Path $script:AgentsDir "$name.md") -Value $content -Encoding UTF8
        }

        $script:RulesPath = Join-Path $TestDrive 'team-rules.json'
        @{
            default = @{ priority = 'P2'; owner = 'ScrumMaster'; source = 'Test' }
            rules   = @(
                @{ pattern = 'API'; priority = 'P1'; owner = 'DevAPI' }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $script:RulesPath -Encoding UTF8
    }

    Context 'API タスクの場合' {
        It 'P1 優先度が設定されること' {
            $team = New-AgentTeam -TaskDescription 'Create REST API endpoint' -AgentsDir $script:AgentsDir -RulesPath $script:RulesPath
            $team.priority | Should -Be 'P1'
        }

        It 'dev-api が specialist に含まれること' {
            $team = New-AgentTeam -TaskDescription 'REST API implementation' -AgentsDir $script:AgentsDir -RulesPath $script:RulesPath
            @($team.specialists) | Where-Object { $_.id -eq 'dev-api' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Core Team の構成' {
        It '7 つの Core Role が含まれること' {
            $team = New-AgentTeam -TaskDescription 'general task' -AgentsDir $script:AgentsDir -RulesPath $script:RulesPath
            @($team.coreTeam).Count | Should -Be 7
        }

        It 'CTO ロールが含まれること' {
            $team = New-AgentTeam -TaskDescription 'test task' -AgentsDir $script:AgentsDir -RulesPath $script:RulesPath
            $cto = @($team.coreTeam) | Where-Object { $_.role -eq 'CTO' }
            $cto | Should -Not -BeNullOrEmpty
        }
    }

    Context 'taskTypes の検出' {
        It 'database タスクが検出されること' {
            $team = New-AgentTeam -TaskDescription 'Database migration for user table' -AgentsDir $script:AgentsDir -RulesPath $script:RulesPath
            $team.taskTypes | Should -Contain 'database'
        }
    }
}

Describe 'Format-AgentTeamDiscussion' {

    Context '正常なチームの場合' {
        It '文字列を返すこと' {
            $team = New-AgentTeam -TaskDescription 'test task' -AgentsDir (Join-Path $TestDrive 'nonexistent')
            $result = Format-AgentTeamDiscussion -Team $team -Topic 'Test topic'
            $result | Should -BeOfType [string]
        }

        It 'Topic が含まれること' {
            $team = New-AgentTeam -TaskDescription 'test task' -AgentsDir (Join-Path $TestDrive 'nonexistent')
            $result = Format-AgentTeamDiscussion -Team $team -Topic 'Important decision'
            $result | Should -Match 'Important decision'
        }

        It 'CTO ロールが含まれること' {
            $team = New-AgentTeam -TaskDescription 'test task' -AgentsDir (Join-Path $TestDrive 'nonexistent')
            $result = Format-AgentTeamDiscussion -Team $team -Topic 'test'
            $result | Should -Match 'CTO'
        }
    }
}

Describe 'Show-AgentTeamComposition' {

    Context '正常なチームの場合' {
        It 'エラーなしで実行できること' {
            $team = New-AgentTeam -TaskDescription 'Build REST API' -AgentsDir (Join-Path $TestDrive 'nonexistent')
            { Show-AgentTeamComposition -Team $team } | Should -Not -Throw
        }
    }
}

Describe 'Get-AgentTeamReport' {

    Context '実プロジェクトルートの場合' {
        It 'agent 定義を読み込めること' {
            $report = Get-AgentTeamReport -ProjectRoot $script:RepoRoot
            $report.agentsDirExists | Should -Be $true
            $report.agentCount | Should -BeGreaterOrEqual 15  # 棚卸し 2026Q2 後の最小値 (実態: 17)
        }

        It 'rules ファイルが存在すること' {
            $report = Get-AgentTeamReport -ProjectRoot $script:RepoRoot
            $report.rulesExist | Should -Be $true
        }
    }

    Context 'TaskDescription を指定した場合' {
        It 'team が生成されること' {
            $report = Get-AgentTeamReport -ProjectRoot $script:RepoRoot -TaskDescription 'Fix CI build errors'
            $report.team | Should -Not -BeNullOrEmpty
            $report.team.taskTypes | Should -Contain 'ci'
        }
    }

    Context 'TaskDescription を指定しない場合' {
        It 'team が null であること' {
            $report = Get-AgentTeamReport -ProjectRoot $script:RepoRoot
            $report.team | Should -BeNullOrEmpty
        }
    }
}

Describe 'Show-AgentTeamReport' {

    Context '正常なレポートの場合' {
        It 'エラーなしで実行できること' {
            $report = Get-AgentTeamReport -ProjectRoot $script:RepoRoot -TaskDescription 'Test task'
            { Show-AgentTeamReport -Report $report } | Should -Not -Throw
        }
    }

    Context 'エージェントなしのレポートの場合' {
        It 'エラーなしで実行できること' {
            $report = [pscustomobject]@{
                agentsDir       = 'nonexistent'
                agentsDirExists = $false
                agentCount      = 0
                agents          = @()
                rulesPath       = 'nonexistent'
                rulesExist      = $false
                team            = $null
            }
            { Show-AgentTeamReport -Report $report } | Should -Not -Throw
        }
    }
}
