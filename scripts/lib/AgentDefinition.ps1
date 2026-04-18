# ============================================================
# AgentDefinition.ps1 - エージェント定義・ローダー・タスク分析
# ============================================================

# Core role definitions (script scope — shared with dot-sourced siblings)
$script:CoreRoles = @(
    [pscustomobject]@{ role = 'CTO';       emoji = '🧠'; agents = @('loop-operator', 'planner') }
    [pscustomobject]@{ role = 'Architect';  emoji = '🏗'; agents = @('architect', 'api-designer') }
    [pscustomobject]@{ role = 'Developer';  emoji = '👨‍💻'; agents = @() }
    [pscustomobject]@{ role = 'QA';         emoji = '🧪'; agents = @('qa', 'tdd-guide', 'e2e-runner') }
    [pscustomobject]@{ role = 'Security';   emoji = '🔐'; agents = @('security', 'security-reviewer') }
    [pscustomobject]@{ role = 'DevOps';     emoji = '🚀'; agents = @('ops', 'release-manager') }
    [pscustomobject]@{ role = 'Reviewer';   emoji = '🔎'; agents = @('code-reviewer') }
)

$script:TaskTypePatterns = @(
    [pscustomobject]@{ type = 'api';       pattern = 'API|REST|endpoint|backend|サーバー';                      agents = @('dev-api', 'api-designer') }
    [pscustomobject]@{ type = 'ui';        pattern = 'UI|frontend|フロントエンド|React|Vue|画面';               agents = @('dev-ui') }
    [pscustomobject]@{ type = 'database';  pattern = 'DB|database|migration|スキーマ|テーブル';                 agents = @('database-reviewer') }
    [pscustomobject]@{ type = 'security';  pattern = 'security|auth|認証|権限|脆弱性|secret';                  agents = @('security-reviewer') }
    [pscustomobject]@{ type = 'ci';        pattern = 'CI|CD|pipeline|Actions|build|デプロイ';                   agents = @('ops', 'build-error-resolver') }
    [pscustomobject]@{ type = 'test';      pattern = 'test|テスト|Pester|Jest|E2E|品質';                       agents = @('tester', 'tdd-guide', 'e2e-runner') }
    [pscustomobject]@{ type = 'refactor';  pattern = 'refactor|リファクタ|整理|命名|技術負債';                  agents = @('refactor-cleaner') }
    [pscustomobject]@{ type = 'docs';      pattern = 'docs|README|ドキュメント|documentation';                  agents = @('doc-updater') }
    [pscustomobject]@{ type = 'incident';  pattern = 'incident|障害|緊急|ダウン|復旧';                          agents = @('incident-triager', 'build-error-resolver') }
    [pscustomobject]@{ type = 'typescript';pattern = 'TypeScript|ts|tsx|Node\.js';                              agents = @('typescript-reviewer') }
    [pscustomobject]@{ type = 'python';    pattern = 'Python|Django|Flask|FastAPI|pip';                         agents = @('python-reviewer') }
    [pscustomobject]@{ type = 'go';        pattern = 'Go|golang|go\.mod';                                      agents = @('go-reviewer', 'go-build-resolver') }
    [pscustomobject]@{ type = 'rust';      pattern = 'Rust|cargo|Cargo\.toml';                                  agents = @('rust-reviewer', 'rust-build-resolver') }
    [pscustomobject]@{ type = 'java';      pattern = 'Java|Spring|Maven|Gradle';                                agents = @('java-reviewer', 'java-build-resolver') }
    [pscustomobject]@{ type = 'cpp';       pattern = 'C\+\+|cpp|CMake';                                        agents = @('cpp-reviewer', 'cpp-build-resolver') }
    [pscustomobject]@{ type = 'kotlin';    pattern = 'Kotlin|Android';                                          agents = @('kotlin-reviewer', 'kotlin-build-resolver') }
)

<#
.SYNOPSIS
    Loads agent definitions from .md files in the specified agents directory.
#>
function Import-AgentDefinition {
    param(
        [Parameter(Mandatory)]
        [string]$AgentsDir
    )

    $agents = @()
    if (-not (Test-Path $AgentsDir)) {
        return $agents
    }

    foreach ($file in @(Get-ChildItem -Path $AgentsDir -Filter '*.md' -File | Where-Object { $_.Name -ne 'CLAUDE.md' })) {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $agent = [ordered]@{
            id          = $file.BaseName
            name        = $file.BaseName
            description = ''
            tools       = @()
            filePath    = $file.FullName
        }

        if ($content -match '(?s)^---\s*\r?\n(.+?)\r?\n---') {
            $frontmatter = $Matches[1]
            foreach ($line in ($frontmatter -split '\r?\n')) {
                if ($line -match '^name:\s*(.+)$') {
                    $agent.name = $Matches[1].Trim()
                }
                elseif ($line -match '^description:\s*(.+)$') {
                    $agent.description = $Matches[1].Trim()
                }
                elseif ($line -match '^tools:\s*(.+)$') {
                    $agent.tools = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                }
            }
        }

        if (-not $agent.description) {
            $bodyLines = ($content -replace '(?s)^---\s*\r?\n.+?\r?\n---\s*\r?\n', '') -split '\r?\n'
            foreach ($bodyLine in $bodyLines) {
                $trimmed = $bodyLine.Trim()
                if ($trimmed -and $trimmed -notmatch '^#') {
                    $agent.description = $trimmed
                    break
                }
            }
        }

        $agents += [pscustomobject]$agent
    }

    return $agents
}

<#
.SYNOPSIS
    Analyzes a task description and returns matched task types and specialist agent IDs.
#>
function Get-TaskTypeAnalysis {
    param(
        [Parameter(Mandatory)]
        [string]$TaskDescription
    )

    $matchedTypes = @()
    $matchedAgents = @()

    foreach ($tp in $script:TaskTypePatterns) {
        if ($TaskDescription -match $tp.pattern) {
            $matchedTypes += $tp.type
            $matchedAgents += $tp.agents
        }
    }

    $matchedAgents = @($matchedAgents | Select-Object -Unique)

    if ($matchedTypes.Count -eq 0) {
        $matchedTypes = @('general')
    }

    return [pscustomobject]@{
        types  = $matchedTypes
        agents = $matchedAgents
    }
}

<#
.SYNOPSIS
    Matches a task description against backlog rules to determine priority and owner.
#>
function Get-BacklogRuleMatch {
    param(
        [Parameter(Mandatory)]
        [string]$TaskDescription,
        [string]$RulesPath
    )

    $result = [pscustomobject]@{
        priority = 'P2'
        owner    = 'ScrumMaster'
        source   = 'AgentTeamsMatrix'
        matched  = $false
    }

    if (-not $RulesPath -or -not (Test-Path $RulesPath)) {
        return $result
    }

    try {
        $rules = Get-Content -Path $RulesPath -Raw -Encoding UTF8 | ConvertFrom-Json

        foreach ($rule in @($rules.rules)) {
            if ($TaskDescription -match $rule.pattern) {
                $result.priority = $rule.priority
                $result.owner = $rule.owner
                $result.matched = $true
                break
            }
        }

        if (-not $result.matched -and $rules.default) {
            $result.priority = $rules.default.priority
            $result.owner = $rules.default.owner
            $result.source = $rules.default.source
        }
    }
    catch {
        Write-Debug "Agent rules file parse error (using defaults): $_"
    }

    return $result
}
