# ============================================================
# AgentTeams.Tests.ps1 - AgentTeams.psm1 unit tests
# Pester 5.x  /  Phase 4 unit tests
# ============================================================

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\lib\AgentTeams.psm1'
    Import-Module $script:ModulePath -Force
}

Describe 'Get-TaskTypeAnalysis' {

    Context 'API 関連タスク' {

        It 'API キーワードで type=api を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Implement REST API endpoint'
            $result.types | Should -Contain 'api'
        }

        It 'backend キーワードで type=api を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Add backend validation'
            $result.types | Should -Contain 'api'
        }
    }

    Context 'UI 関連タスク' {

        It 'UI キーワードで type=ui を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Fix UI rendering bug'
            $result.types | Should -Contain 'ui'
        }

        It 'React キーワードで type=ui を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Upgrade React components'
            $result.types | Should -Contain 'ui'
        }
    }

    Context 'セキュリティ関連タスク' {

        It 'security キーワードで type=security を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Review security settings'
            $result.types | Should -Contain 'security'
        }

        It '認証キーワードで type=security を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription '認証フローを修正する'
            $result.types | Should -Contain 'security'
        }
    }

    Context 'テスト関連タスク' {

        It 'test キーワードで type=test を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Add unit test for parser'
            $result.types | Should -Contain 'test'
        }

        It 'Pester キーワードで type=test を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Write Pester tests for module'
            $result.types | Should -Contain 'test'
        }
    }

    Context 'CI 関連タスク' {

        It 'CI キーワードで type=ci を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Fix CI pipeline failure'
            $result.types | Should -Contain 'ci'
        }

        It 'Actions キーワードで type=ci を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Update GitHub Actions workflow'
            $result.types | Should -Contain 'ci'
        }
    }

    Context 'ドキュメント関連タスク' {

        It 'README キーワードで type=docs を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Update README with new instructions'
            $result.types | Should -Contain 'docs'
        }
    }

    Context 'マッチなしのタスク' {

        It '無関係なタスクは type=general を返す' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Organize coffee supply'
            $result.types | Should -Contain 'general'
        }

        It '無関係なタスクの agents は空' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Organize coffee supply'
            $result.agents | Should -HaveCount 0
        }
    }

    Context '複数マッチのタスク' {

        It 'API+test で複数 type が返る' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Add API test coverage'
            $result.types | Should -Contain 'api'
            $result.types | Should -Contain 'test'
        }

        It '重複 agent は排除される' {
            $result = Get-TaskTypeAnalysis -TaskDescription 'Add API test for backend'
            $uniqueAgents = $result.agents | Select-Object -Unique
            $result.agents.Count | Should -Be $uniqueAgents.Count
        }
    }
}

Describe 'Get-BacklogRuleMatch' {

    Context 'ルールファイルが存在しない場合' {

        It 'デフォルト priority P2 を返す' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Any task' -RulesPath ''
            $result.priority | Should -Be 'P2'
        }

        It 'デフォルト owner ScrumMaster を返す' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Any task' -RulesPath ''
            $result.owner | Should -Be 'ScrumMaster'
        }

        It 'matched は false を返す' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Any task' -RulesPath ''
            $result.matched | Should -Be $false
        }
    }

    Context 'ルールファイルパスが存在しないパス' {

        It '存在しないパスでもデフォルトを返す (エラーなし)' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Any task' -RulesPath 'C:\nonexistent\rules.json'
            $result.priority | Should -Be 'P2'
        }
    }

    Context 'ルールファイルが有効な場合' {

        BeforeEach {
            $script:RulesFile = Join-Path $TestDrive 'rules.json'
            $rules = @{
                rules = @(
                    @{ pattern = 'security|auth'; priority = 'P1'; owner = 'Security' }
                    @{ pattern = 'docs|README';   priority = 'P3'; owner = 'Tech Writer' }
                )
                default = @{ priority = 'P2'; owner = 'Developer'; source = 'AgentTeamsMatrix' }
            }
            $rules | ConvertTo-Json -Depth 5 | Set-Content -Path $script:RulesFile -Encoding UTF8
        }

        It 'security パターンにマッチして P1 を返す' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Fix auth security issue' -RulesPath $script:RulesFile
            $result.priority | Should -Be 'P1'
        }

        It 'security パターンにマッチして owner Security を返す' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Fix auth security issue' -RulesPath $script:RulesFile
            $result.owner | Should -Be 'Security'
        }

        It 'security マッチで matched = true' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Fix auth security issue' -RulesPath $script:RulesFile
            $result.matched | Should -Be $true
        }

        It 'docs パターンにマッチして P3 を返す' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Update README documentation' -RulesPath $script:RulesFile
            $result.priority | Should -Be 'P3'
        }

        It 'マッチなしの場合はデフォルト P2 を返す' {
            $result = Get-BacklogRuleMatch -TaskDescription 'Refactor logging module' -RulesPath $script:RulesFile
            $result.priority | Should -Be 'P2'
        }
    }
}
