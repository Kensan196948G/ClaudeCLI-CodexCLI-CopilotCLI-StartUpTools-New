BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:PluginRoot = Join-Path $script:RepoRoot '.claude\claudeos'
}

Describe 'ClaudeOS Plugin Structure' {

    It 'plugin.json が存在し有効な JSON であること' {
        $pluginJsonPath = Join-Path $script:PluginRoot '.claude-plugin\plugin.json'
        (Test-Path $pluginJsonPath) | Should -BeTrue
        $json = Get-Content $pluginJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $json.name | Should -Not -BeNullOrEmpty
        $json.version | Should -Match '^\d+\.\d+\.\d+$'
        $json.description | Should -Not -BeNullOrEmpty
    }

    It 'plugin.json の components パスが全て存在すること' {
        $pluginJsonPath = Join-Path $script:PluginRoot '.claude-plugin\plugin.json'
        $json = Get-Content $pluginJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $components = $json.components
        @(
            $components.agentsPath,
            $components.skillsPath,
            $components.commandsPath,
            $components.rulesPath,
            $components.hooksPath,
            $components.scriptsPath,
            $components.contextsPath,
            $components.examplesPath,
            $components.mcpConfigsPath
        ) | ForEach-Object {
            $resolvedPath = Join-Path $script:PluginRoot $_
            (Test-Path $resolvedPath) | Should -BeTrue -Because "component path '$_' should exist"
        }
    }
}

Describe 'ClaudeOS Agents' {

    BeforeAll {
        $script:AgentFiles = Get-ChildItem (Join-Path $script:PluginRoot 'agents') -Filter '*.md'
        $script:FrontmatterAgents = $script:AgentFiles | Where-Object {
            (Get-Content $_.FullName -TotalCount 1 -Encoding UTF8) -match '^---'
        }
        $script:MarkdownAgents = $script:AgentFiles | Where-Object {
            (Get-Content $_.FullName -TotalCount 1 -Encoding UTF8) -match '^#\s+'
        }
    }

    It 'エージェント定義ファイルが存在すること' {
        $script:AgentFiles.Count | Should -BeGreaterThan 0
    }

    It '全エージェントがフロントマターまたは Markdown ヘッダー形式であること' {
        foreach ($file in $script:AgentFiles) {
            $firstLine = (Get-Content $file.FullName -TotalCount 1 -Encoding UTF8)
            ($firstLine -match '^---' -or $firstLine -match '^#\s+') | Should -BeTrue -Because "$($file.Name) should start with frontmatter or heading"
        }
    }

    It 'フロントマター形式のエージェントに name フィールドがあること' {
        foreach ($file in $script:FrontmatterAgents) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8
            $content | Should -Match '(?m)^name:\s*.+' -Because "$($file.Name) should have a name field"
        }
    }

    It 'フロントマター形式のエージェントに description フィールドがあること' {
        foreach ($file in $script:FrontmatterAgents) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8
            $content | Should -Match '(?m)^description:\s*.+' -Because "$($file.Name) should have a description field"
        }
    }

    It 'フロントマター形式のエージェントに tools フィールドがあること' {
        foreach ($file in $script:FrontmatterAgents) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8
            $content | Should -Match '(?m)^tools:\s*.+' -Because "$($file.Name) should have a tools field"
        }
    }

    It 'Markdown 形式のエージェントに説明があること' {
        foreach ($file in $script:MarkdownAgents) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8
            $content.Trim().Length | Should -BeGreaterThan 10 -Because "$($file.Name) should have meaningful content"
        }
    }
}

Describe 'ClaudeOS Skills' {

    BeforeAll {
        $script:SkillDirs = Get-ChildItem (Join-Path $script:PluginRoot 'skills') -Directory
    }

    It 'スキルディレクトリが存在すること' {
        $script:SkillDirs.Count | Should -BeGreaterThan 0
    }

    It '全スキルに SKILL.md が存在すること' {
        foreach ($dir in $script:SkillDirs) {
            $skillMd = Join-Path $dir.FullName 'SKILL.md'
            (Test-Path $skillMd) | Should -BeTrue -Because "$($dir.Name) should have SKILL.md"
        }
    }

    It '全スキルの SKILL.md が空でないこと' {
        foreach ($dir in $script:SkillDirs) {
            $skillMd = Join-Path $dir.FullName 'SKILL.md'
            $content = Get-Content $skillMd -Raw -Encoding UTF8
            $content.Trim().Length | Should -BeGreaterThan 10 -Because "$($dir.Name)/SKILL.md should have content"
        }
    }
}

Describe 'ClaudeOS Commands' {

    BeforeAll {
        $script:CommandFiles = Get-ChildItem (Join-Path $script:PluginRoot 'commands') -Filter '*.md'
    }

    It 'コマンド定義ファイルが存在すること' {
        $script:CommandFiles.Count | Should -BeGreaterThan 0
    }

    It '全コマンドが見出しで始まること' {
        foreach ($file in $script:CommandFiles) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8
            $content | Should -Match '^#\s+/' -Because "$($file.Name) should start with a command heading like '# /name'"
        }
    }
}

Describe 'ClaudeOS Scripts' {

    It 'utils.js が存在し関数をエクスポートしていること' {
        $utilsPath = Join-Path $script:PluginRoot 'scripts\lib\utils.js'
        (Test-Path $utilsPath) | Should -BeTrue
        $content = Get-Content $utilsPath -Raw -Encoding UTF8
        $content | Should -Match 'export\s+function'
    }

    It 'フックスクリプトが存在すること' {
        $hookScripts = Get-ChildItem (Join-Path $script:PluginRoot 'scripts\hooks') -Filter '*.js'
        $hookScripts.Count | Should -BeGreaterThan 0
    }

    It 'フックスクリプトの構文が有効であること' {
        $hookScripts = Get-ChildItem (Join-Path $script:PluginRoot 'scripts\hooks') -Filter '*.js'
        foreach ($script_ in $hookScripts) {
            & node --check $script_.FullName 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0 -Because "$($script_.Name) should have valid JS syntax"
        }
    }
}

Describe 'ClaudeOS Rules' {

    It 'ルールファイルが存在すること' {
        $ruleFiles = Get-ChildItem (Join-Path $script:PluginRoot 'rules') -Filter '*.md' -Recurse
        $ruleFiles.Count | Should -BeGreaterThan 0
    }

    It '全ルールが空でないこと' {
        $ruleFiles = Get-ChildItem (Join-Path $script:PluginRoot 'rules') -Filter '*.md' -Recurse
        foreach ($file in $ruleFiles) {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8
            $content.Trim().Length | Should -BeGreaterThan 5 -Because "$($file.Name) should have content"
        }
    }
}

Describe 'ClaudeOS System Kernel' {

    It 'orchestrator.md が存在すること' {
        $path = Join-Path $script:PluginRoot 'system\orchestrator.md'
        (Test-Path $path) | Should -BeTrue
    }

    It 'system ディレクトリに必須ファイルが揃っていること' {
        $systemDir = Join-Path $script:PluginRoot 'system'
        $files = Get-ChildItem $systemDir -Filter '*.md' | Select-Object -ExpandProperty Name
        $files | Should -Contain 'orchestrator.md'
    }
}
