# ============================================================
# NewCloudSchedule.Tests.ps1 - New-CloudSchedule.ps1 unit tests
# Pester 5.x / Issue #226
#
# Strategy: dot-source the script with exit->return patching so the
# Pester process is not terminated by the -NonInteractive exit 0.
# A fake claude.cmd stub is added to PATH to satisfy the CLI check.
# ============================================================

BeforeAll {
    $script:RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts\main\New-CloudSchedule.ps1'

    # --- Fake claude stub (satisfies the CLI-detection block) ---
    $script:TempDir   = Join-Path ([System.IO.Path]::GetTempPath()) 'pester-cloudschedule-tests'
    $null = New-Item -ItemType Directory -Path $script:TempDir -Force
    '@echo off' | Set-Content (Join-Path $script:TempDir 'claude.cmd') -Encoding ASCII
    $script:SavedPath = $env:PATH
    $env:PATH         = "$script:TempDir;$env:PATH"

    # --- Patch: replace 'exit <n>' with 'return' to prevent killing Pester ---
    $raw     = Get-Content $script:ScriptPath -Raw -Encoding UTF8
    $patched = $raw -replace '(?m)^\s*exit\s+\d+\s*$', 'return'
    $script:TempScript = Join-Path $script:TempDir 'NewCloudSchedule.tmp.ps1'
    $patched | Set-Content $script:TempScript -Encoding UTF8

    # Dot-source in NonInteractive mode: defines all functions, sets script: vars, then returns
    . $script:TempScript -NonInteractive
}

AfterAll {
    $env:PATH = $script:SavedPath
    if (Test-Path $script:TempDir) { Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# ============================================================
# New-LoopPreset
# ============================================================
Describe 'New-LoopPreset' {

    It 'returns exactly 4 presets' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        $result.Count | Should -Be 4
    }

    It 'preset 0 is named ClaudeOS Monitor' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        $result[0].Name | Should -Be 'ClaudeOS Monitor'
    }

    It 'Monitor cron is hourly on Mon-Sat (0 * * * 1-6)' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        $result[0].Cron | Should -Be '0 * * * 1-6'
    }

    It 'preset 1 is named ClaudeOS Development' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        $result[1].Name | Should -Be 'ClaudeOS Development'
    }

    It 'Development cron is every 2 hours on Mon-Sat (0 */2 * * 1-6)' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        $result[1].Cron | Should -Be '0 */2 * * 1-6'
    }

    It 'preset 2 is named ClaudeOS Verify with hourly cron' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        $result[2].Name | Should -Be 'ClaudeOS Verify'
        $result[2].Cron | Should -Be '0 * * * 1-6'
    }

    It 'preset 3 is named ClaudeOS Improvement with hourly cron' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        $result[3].Name | Should -Be 'ClaudeOS Improvement'
        $result[3].Cron | Should -Be '0 * * * 1-6'
    }

    It 'injects repository URL into every Content field' {
        $url        = 'https://github.com/TestOrg/my-special-repo'
        $urlPattern = [regex]::Escape($url)
        $result     = New-LoopPreset -Url $url
        foreach ($preset in $result) {
            $preset.Content | Should -Match $urlPattern
        }
    }

    It 'each preset has Label, Name, Cron, Content properties' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        foreach ($preset in $result) {
            $preset.PSObject.Properties.Name | Should -Contain 'Label'
            $preset.PSObject.Properties.Name | Should -Contain 'Name'
            $preset.PSObject.Properties.Name | Should -Contain 'Cron'
            $preset.PSObject.Properties.Name | Should -Contain 'Content'
        }
    }

    It 'all Content values are non-empty' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        foreach ($preset in $result) {
            $preset.Content.Trim() | Should -Not -BeNullOrEmpty
        }
    }

    It 'each preset Label is non-empty' {
        $result = New-LoopPreset -Url 'https://github.com/test/repo'
        foreach ($preset in $result) {
            $preset.Label | Should -Not -BeNullOrEmpty
        }
    }

    It 'accepts different repository URLs without error' {
        { New-LoopPreset -Url 'https://github.com/another-org/another-repo' } | Should -Not -Throw
    }
}

# ============================================================
# Build-CreatePrompt
# ============================================================
Describe 'Build-CreatePrompt' {

    It 'contains RemoteTrigger creation instruction' {
        $result = Build-CreatePrompt -Name 'TestTrigger' -Cron '0 * * * 1-6' -PromptContent 'hello'
        $result | Should -Match 'RemoteTrigger'
    }

    It 'embeds Name in prompt output' {
        $result = Build-CreatePrompt -Name 'ClaudeOS Monitor' -Cron '0 * * * 1-6' -PromptContent 'content'
        $result | Should -Match '"ClaudeOS Monitor"'
    }

    It 'embeds Cron expression in prompt output' {
        $cronPattern = [regex]::Escape('"0 */2 * * 1-6"')
        $result      = Build-CreatePrompt -Name 'T' -Cron '0 */2 * * 1-6' -PromptContent 'content'
        $result | Should -Match $cronPattern
    }

    It 'sets enabled: true' {
        $result = Build-CreatePrompt -Name 'T' -Cron '0 * * * 1-6' -PromptContent 'x'
        $result | Should -Match 'enabled: true'
    }

    It 'sets model to claude-sonnet-4-6' {
        $result = Build-CreatePrompt -Name 'T' -Cron '0 * * * 1-6' -PromptContent 'x'
        $result | Should -Match 'claude-sonnet-4-6'
    }

    It 'escapes double-quotes in PromptContent' {
        $result = Build-CreatePrompt -Name 'T' -Cron '0 * * * 1-6' -PromptContent 'say "hello" now'
        $result | Should -Match '\\"hello\\"'
    }

    It 'escapes newlines in PromptContent as literal \n' {
        $result = Build-CreatePrompt -Name 'T' -Cron '0 * * * 1-6' -PromptContent "line1`nline2"
        # Content field should contain literal \n (2 chars), not a real newline
        $result | Should -Match 'line1\\nline2'
    }

    It 'generates a UUID (RFC 4122 format)' {
        $result = Build-CreatePrompt -Name 'T' -Cron '0 * * * 1-6' -PromptContent 'x'
        $result | Should -Match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    }

    It 'generates a different UUID on each call' {
        $r1 = Build-CreatePrompt -Name 'T' -Cron '0 * * * 1-6' -PromptContent 'x'
        $r2 = Build-CreatePrompt -Name 'T' -Cron '0 * * * 1-6' -PromptContent 'x'
        $uuid1 = [regex]::Match($r1, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value
        $uuid2 = [regex]::Match($r2, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value
        $uuid1 | Should -Not -Be $uuid2
    }

    It 'includes CREATED_ID output instruction' {
        $result = Build-CreatePrompt -Name 'T' -Cron '0 * * * 1-6' -PromptContent 'x'
        $result | Should -Match 'CREATED_ID='
    }

    It 'includes git_repository source URL' {
        $result = Build-CreatePrompt -Name 'T' -Cron '0 * * * 1-6' -PromptContent 'x'
        $result | Should -Match 'git_repository'
    }
}
