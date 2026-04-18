# ============================================================
# E2E.Tests.ps1 - ClaudeOS v3.0.0 End-to-End Integration Tests
# Pester 5.x
#
# Purpose: Validate repository structure, schema integrity, and
#          configuration consistency without relying on external
#          services (GitHub API, Claude CLI). Safe for CI.
# Issue: #124
#
# NOTE: Data-driven Context/foreach blocks use BeforeDiscovery so
#       variables are available at test-discovery time (Pester 5).
# ============================================================

BeforeDiscovery {
    $script:RepoRoot    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ClaudeOsDir = Join-Path $script:RepoRoot '.claude\claudeos'
    $script:AgentsDir   = Join-Path $script:ClaudeOsDir 'agents'
    $script:SkillsDir   = Join-Path $script:ClaudeOsDir 'skills'
    $script:HooksDir    = Join-Path $script:ClaudeOsDir 'hooks'
    $script:HooksJson   = Join-Path $script:HooksDir 'hooks.json'

    # Load for data-driven tests
    if (Test-Path $script:HooksJson) {
        $hooksConfig = Get-Content $script:HooksJson -Raw | ConvertFrom-Json
        $script:PreToolUseHooks  = @($hooksConfig.PreToolUse)  | Where-Object { $_ -ne $null -and $_.name }
        $script:PostToolUseHooks = @($hooksConfig.PostToolUse) | Where-Object { $_ -ne $null -and $_.name }
    } else {
        $script:PreToolUseHooks  = @()
        $script:PostToolUseHooks = @()
    }

    if (Test-Path $script:AgentsDir) {
        $script:AgentFiles = Get-ChildItem -Path $script:AgentsDir -Filter '*.md' |
            Where-Object { $_.Name -ne 'CLAUDE.md' }
    } else {
        $script:AgentFiles = @()
    }

    if (Test-Path $script:SkillsDir) {
        $script:SkillDirs = Get-ChildItem -Path $script:SkillsDir -Directory
    } else {
        $script:SkillDirs = @()
    }
}

BeforeAll {
    $script:RepoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ClaudeOsDir  = Join-Path $script:RepoRoot '.claude\claudeos'
    $script:AgentsDir    = Join-Path $script:ClaudeOsDir 'agents'
    $script:SkillsDir    = Join-Path $script:ClaudeOsDir 'skills'
    $script:HooksDir     = Join-Path $script:ClaudeOsDir 'hooks'
    $script:HooksJson    = Join-Path $script:HooksDir 'hooks.json'
    $script:StateExample = Join-Path $script:RepoRoot 'state.json.example'
}

# ────────────────────────────────────────────────────────────
# Describe 1: Repository Structure
# ────────────────────────────────────────────────────────────
Describe 'Repository Structure' {

    It 'CLAUDE.md がルートに存在すること' {
        Join-Path $script:RepoRoot 'CLAUDE.md' | Should -Exist
    }

    It 'state.json.example が存在すること' {
        Join-Path $script:RepoRoot 'state.json.example' | Should -Exist
    }

    It 'README.md が存在すること' {
        Join-Path $script:RepoRoot 'README.md' | Should -Exist
    }

    It '.claude/claudeos ディレクトリが存在すること' {
        $script:ClaudeOsDir | Should -Exist
    }

    It 'agents ディレクトリが存在すること' {
        $script:AgentsDir | Should -Exist
    }

    It 'hooks ディレクトリが存在すること' {
        $script:HooksDir | Should -Exist
    }

    It 'hooks.json が存在すること' {
        $script:HooksJson | Should -Exist
    }

    It 'tests ディレクトリが存在すること' {
        Join-Path $script:RepoRoot 'tests' | Should -Exist
    }

    It '.github/workflows/ci.yml が存在すること' {
        Join-Path $script:RepoRoot '.github\workflows\ci.yml' | Should -Exist
    }

    It 'scripts/lib ディレクトリが存在すること' {
        Join-Path $script:RepoRoot 'scripts\lib' | Should -Exist
    }

    Context 'claudeos サブディレクトリ構造' {
        foreach ($subDir in @('agents', 'hooks', 'loops', 'system', 'evolution', 'skills', 'commands')) {
            It "$subDir ディレクトリが .claude/claudeos 下に存在すること" -TestCases @{ SubDir = $subDir; ClaudeOsDir = $script:ClaudeOsDir } {
                Join-Path $ClaudeOsDir $SubDir | Should -Exist
            }
        }
    }
}

# ────────────────────────────────────────────────────────────
# Describe 2: state.json.example Schema Validation
# ────────────────────────────────────────────────────────────
Describe 'state.json.example Schema Validation' {

    BeforeAll {
        $script:StateSchema = Get-Content $script:StateExample -Raw | ConvertFrom-Json
    }

    It 'JSON として正常にパースできること' {
        $script:StateSchema | Should -Not -BeNullOrEmpty
    }

    It 'goal ブロックが存在すること' {
        $script:StateSchema.PSObject.Properties.Name | Should -Contain 'goal'
    }

    It 'execution ブロックが存在すること' {
        $script:StateSchema.PSObject.Properties.Name | Should -Contain 'execution'
    }

    It 'session ブロックが存在すること (v3.0.0 追加)' {
        $script:StateSchema.PSObject.Properties.Name | Should -Contain 'session'
    }

    It 'session.context_load_tier が存在すること' {
        $script:StateSchema.session.PSObject.Properties.Name | Should -Contain 'context_load_tier'
    }

    It 'frontier ブロックが存在すること (v3.0.0 追加)' {
        $script:StateSchema.PSObject.Properties.Name | Should -Contain 'frontier'
    }

    It 'frontier.last_test_date フィールドが存在すること' {
        $script:StateSchema.frontier.PSObject.Properties.Name | Should -Contain 'last_test_date'
    }

    It 'improvement ブロックが存在すること (v3.0.0 追加)' {
        $script:StateSchema.PSObject.Properties.Name | Should -Contain 'improvement'
    }

    It 'improvement.stop_doing_review_date フィールドが存在すること' {
        $script:StateSchema.improvement.PSObject.Properties.Name | Should -Contain 'stop_doing_review_date'
    }

    It 'learning ブロックが存在すること (v3.0.0 追加)' {
        $script:StateSchema.PSObject.Properties.Name | Should -Contain 'learning'
    }

    It 'learning.usage_history フィールドが存在すること' {
        $script:StateSchema.learning.PSObject.Properties.Name | Should -Contain 'usage_history'
    }

    It 'learning.dead_weight フィールドが存在すること' {
        $script:StateSchema.learning.PSObject.Properties.Name | Should -Contain 'dead_weight'
    }

    It 'codex ブロックが存在すること' {
        $script:StateSchema.PSObject.Properties.Name | Should -Contain 'codex'
    }

    It 'debug ブロックが存在すること' {
        $script:StateSchema.PSObject.Properties.Name | Should -Contain 'debug'
    }

    It 'token ブロックが存在すること' {
        $script:StateSchema.PSObject.Properties.Name | Should -Contain 'token'
    }

    It 'execution.max_duration_minutes が正の数値であること' {
        # ConvertFrom-Json は整数を [long] として返すため BeGreaterThan で検証
        $script:StateSchema.execution.max_duration_minutes | Should -BeGreaterThan 0
    }

    It 'kpi.success_rate_target が 0〜1 の範囲であること' {
        $rate = $script:StateSchema.kpi.success_rate_target
        $rate | Should -BeGreaterOrEqual 0
        $rate | Should -BeLessOrEqual 1
    }
}

# ────────────────────────────────────────────────────────────
# Describe 3: hooks.json Integrity
# ────────────────────────────────────────────────────────────
Describe 'hooks.json Integrity' {

    BeforeAll {
        $script:HooksConfig = Get-Content $script:HooksJson -Raw | ConvertFrom-Json
    }

    It 'JSON として正常にパースできること' {
        $script:HooksConfig | Should -Not -BeNullOrEmpty
    }

    It 'PreToolUse エントリが存在すること' {
        $script:HooksConfig.PSObject.Properties.Name | Should -Contain 'PreToolUse'
    }

    It 'PostToolUse エントリが存在すること' {
        $script:HooksConfig.PSObject.Properties.Name | Should -Contain 'PostToolUse'
    }

    It 'safety-check が PreToolUse に登録されていないこと (Issue #121 で削除済み)' {
        $preToolUseNames = @($script:HooksConfig.PreToolUse) | ForEach-Object { $_.name }
        $preToolUseNames | Should -Not -Contain 'safety-check'
    }

    It 'agent-risk-check が PreToolUse に登録されていること' {
        $preToolUseNames = @($script:HooksConfig.PreToolUse) | ForEach-Object { $_.name }
        $preToolUseNames | Should -Contain 'agent-risk-check'
    }

    It 'agent-risk-check の type が agent であること' {
        $hook = @($script:HooksConfig.PreToolUse) | Where-Object { $_.name -eq 'agent-risk-check' }
        $hook.type | Should -Be 'agent'
    }

    Context '登録フックの .md ファイル実体確認 (PreToolUse)' {
        # BeforeDiscovery で $script:PreToolUseHooks を設定済み
        # -TestCases でデータを実行時に渡す (Pester 5 foreach クロージャー対策)
        foreach ($hook in $script:PreToolUseHooks) {
            It "PreToolUse フック '$($hook.name)' に対応する .md が存在すること" -TestCases @{ HookName = $hook.name; HooksDir = $script:HooksDir } {
                $mdPath = Join-Path $HooksDir "$HookName.md"
                $mdPath | Should -Exist
            }
        }
    }

    Context '登録フックの .md またはディレクトリ実体確認 (PostToolUse)' {
        foreach ($hook in $script:PostToolUseHooks) {
            It "PostToolUse フック '$($hook.name)' に対応する .md またはディレクトリが存在すること" -TestCases @{ HookName = $hook.name; HooksDir = $script:HooksDir } {
                $mdPath  = Join-Path $HooksDir "$HookName.md"
                $dirPath = Join-Path $HooksDir $HookName
                ($mdPath | Test-Path) -or ($dirPath | Test-Path) | Should -Be $true
            }
        }
    }
}

# ────────────────────────────────────────────────────────────
# Describe 4: Agent Definition Integrity
# ────────────────────────────────────────────────────────────
Describe 'Agent Definition Integrity' {

    BeforeAll {
        $script:AgentFilesExec = Get-ChildItem -Path $script:AgentsDir -Filter '*.md' |
            Where-Object { $_.Name -ne 'CLAUDE.md' }
    }

    It '17 個以上の Agent 定義ファイルが存在すること (棚卸し 2026Q2 後の最小値)' {
        @($script:AgentFilesExec).Count | Should -BeGreaterOrEqual 17
    }

    Context '各 Agent ファイルの空ファイル検証' {
        foreach ($file in $script:AgentFiles) {
            It "$($file.Name) が空でないこと" -TestCases @{ FileLength = $file.Length } {
                $FileLength | Should -BeGreaterThan 0
            }
        }
    }

    Context 'frontmatter を持つ Agent の name フィールド検証' {
        foreach ($file in $script:AgentFiles) {
            It "$($file.Name) の frontmatter name がファイル名（拡張子なし）と一致すること" -TestCases @{ FilePath = $file.FullName; BaseName = $file.BaseName } {
                $content = Get-Content $FilePath -Raw
                if ($content -match '(?s)^---\s*\r?\n(.*?)\r?\n---') {
                    $frontmatter = $matches[1]
                    if ($frontmatter -match 'name:\s*(.+)') {
                        $nameInFrontmatter = $matches[1].Trim()
                        $nameInFrontmatter | Should -Be $BaseName
                    }
                }
            }
        }
    }
}

# ────────────────────────────────────────────────────────────
# Describe 5: ClaudeOS Loop Files Integrity
# ────────────────────────────────────────────────────────────
Describe 'ClaudeOS Loop Files Integrity' {

    BeforeAll {
        $script:LoopsDir = Join-Path $script:ClaudeOsDir 'loops'
    }

    It 'monitor-loop.md が存在すること' {
        Join-Path $script:LoopsDir 'monitor-loop.md' | Should -Exist
    }

    It 'verify-loop.md が存在すること' {
        Join-Path $script:LoopsDir 'verify-loop.md' | Should -Exist
    }

    It 'improve-loop.md が存在すること' {
        Join-Path $script:LoopsDir 'improve-loop.md' | Should -Exist
    }

    It 'frontier-test-loop.md が存在すること (v3.0.0 追加)' {
        Join-Path $script:LoopsDir 'frontier-test-loop.md' | Should -Exist
    }
}

# ────────────────────────────────────────────────────────────
# Describe 6: ClaudeOS System Files Integrity
# ────────────────────────────────────────────────────────────
Describe 'ClaudeOS System Files Integrity' {

    BeforeAll {
        $script:SystemDir = Join-Path $script:ClaudeOsDir 'system'
    }

    It 'orchestrator.md が存在すること' {
        Join-Path $script:SystemDir 'orchestrator.md' | Should -Exist
    }

    It 'progressive-disclosure.md が存在すること (v3.0.0 追加 Issue #106)' {
        Join-Path $script:SystemDir 'progressive-disclosure.md' | Should -Exist
    }

    Context 'claudeos/frontier ディレクトリ検証 (v3.0.0 追加)' {
        It 'frontier ディレクトリが存在すること' {
            Join-Path $script:ClaudeOsDir 'frontier' | Should -Exist
        }

        It 'benchmark-tasks.md が存在すること (Issue #109)' {
            Join-Path -Path $script:ClaudeOsDir -ChildPath 'frontier\benchmark-tasks.md' | Should -Exist
        }
    }
}

# ────────────────────────────────────────────────────────────
# Describe 7: Skills Directory Integrity
# ────────────────────────────────────────────────────────────
Describe 'Skills Directory Integrity' {

    BeforeAll {
        $script:SkillDirsExec = Get-ChildItem -Path $script:SkillsDir -Directory
    }

    It '10 個以上のスキルディレクトリが存在すること' {
        @($script:SkillDirsExec).Count | Should -BeGreaterOrEqual 10
    }

    Context '各スキルディレクトリに SKILL.md が存在すること' {
        foreach ($skillDir in $script:SkillDirs) {
            It "$($skillDir.Name)/SKILL.md が存在すること" -TestCases @{ SkillDirPath = $skillDir.FullName } {
                $skillMd = Join-Path $SkillDirPath 'SKILL.md'
                $skillMd | Should -Exist
            }
        }
    }
}

# ────────────────────────────────────────────────────────────
# Describe 8: v3.0.0 新規ドキュメント存在確認
# ────────────────────────────────────────────────────────────
Describe 'v3.0.0 New Document Existence (Issue #103-#109)' {

    BeforeAll {
        $script:LoopsDirV3   = Join-Path $script:ClaudeOsDir 'loops'
        $script:SystemDirV3  = Join-Path $script:ClaudeOsDir 'system'
        $script:FrontierDir  = Join-Path $script:ClaudeOsDir 'frontier'
    }

    It 'frontier-test-loop.md が存在すること (Issue #109)' {
        Join-Path $script:LoopsDirV3 'frontier-test-loop.md' | Should -Exist
    }

    It 'progressive-disclosure.md が存在すること (Issue #106)' {
        Join-Path $script:SystemDirV3 'progressive-disclosure.md' | Should -Exist
    }

    It 'benchmark-tasks.md が存在すること (Issue #109)' {
        Join-Path $script:FrontierDir 'benchmark-tasks.md' | Should -Exist
    }

    It 'agent-risk-check.md が存在すること (Issue #104)' {
        Join-Path $script:HooksDir 'agent-risk-check.md' | Should -Exist
    }

    It 'v3 リリースノート MD が存在すること' {
        Join-Path -Path $script:RepoRoot -ChildPath 'docs\common\15_v3リリースノート.md' | Should -Exist
    }
}
