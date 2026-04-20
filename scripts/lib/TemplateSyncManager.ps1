<#
.SYNOPSIS
    Template synchronization functions extracted from LauncherCommon.psm1.
    Handles copying and syncing template files into project directories.
    Dot-sourced by LauncherCommon.psm1 for backward compatibility.
#>

<#
.SYNOPSIS
    Copies a template file to the target path if it differs, creating parent directories as needed.
#>
function Sync-ProjectTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [Parameter(Mandatory)]
        [string]$Label,
        [switch]$EnsureParentDirectory
    )

    if (-not (Test-Path $TemplatePath)) {
        return
    }

    if ($EnsureParentDirectory) {
        $parent = Split-Path -Parent $TargetPath
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }

    $needsCopy = $true
    if (Test-Path $TargetPath) {
        $src = Get-Content $TemplatePath -Raw -Encoding UTF8
        $dst = Get-Content $TargetPath -Raw -Encoding UTF8
        if ($src -eq $dst) {
            $needsCopy = $false
        }
    }

    if ($needsCopy) {
        Copy-Item $TemplatePath $TargetPath -Force
        Write-Host "[OK] $Label を配置/更新しました: $TargetPath" -ForegroundColor Green
    } else {
        Write-Host "[INFO] $Label は最新です: $TargetPath" -ForegroundColor Cyan
    }
}

<#
.SYNOPSIS
    Recursively copies all files from the source directory into the target directory.
#>
function Sync-ProjectDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$SourceDirectory,
        [Parameter(Mandatory)]
        [string]$TargetDirectory,
        [Parameter(Mandatory)]
        [string]$Label
    )

    if (-not (Test-Path $SourceDirectory)) {
        return
    }

    if (-not (Test-Path $TargetDirectory)) {
        New-Item -ItemType Directory -Force -Path $TargetDirectory | Out-Null
    }

    Copy-Item -Path (Join-Path $SourceDirectory '*') -Destination $TargetDirectory -Recurse -Force
    Write-Host "[OK] $Label を配置/更新しました: $TargetDirectory" -ForegroundColor Green
}

<#
.SYNOPSIS
    Recursively syncs each file in the template directory to the corresponding path in the target directory.
#>
function Sync-ProjectTemplateDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$TemplateDir,
        [Parameter(Mandatory)]
        [string]$TargetDir,
        [string]$Label = 'template directory'
    )

    if (-not (Test-Path $TemplateDir)) {
        return
    }

    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    }

    $files = @(Get-ChildItem -Path $TemplateDir -Recurse -File | Sort-Object FullName)
    if ($files.Count -eq 0) {
        return
    }

    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($TemplateDir.Length).TrimStart('\', '/')
        $targetPath = Join-Path $TargetDir $relativePath
        $parentDir = Split-Path -Parent $targetPath
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
        }

        Sync-ProjectTemplate -TemplatePath $file.FullName -TargetPath $targetPath -Label "$Label/$relativePath"
    }
}

<#
.SYNOPSIS
    Copies a template file to the target path only if the target does not already exist.
#>
function Initialize-ProjectTemplate {
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [Parameter(Mandatory)]
        [string]$Label,
        [switch]$EnsureParentDirectory
    )

    if (-not (Test-Path $TemplatePath)) {
        return
    }

    if ($EnsureParentDirectory) {
        $parent = Split-Path -Parent $TargetPath
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }

    if (Test-Path $TargetPath) {
        Write-Host "[INFO] 既存の $Label を維持します: $TargetPath" -ForegroundColor Cyan
        return
    }

    Copy-Item $TemplatePath $TargetPath -Force
    Write-Host "[OK] $Label を初期配置しました: $TargetPath" -ForegroundColor Green
}

<#
.SYNOPSIS
    Syncs Claude global config templates (CLAUDE.md, .claude/claudeos, settings.json, .mcp.json) into the project directory.
#>
function Sync-LauncherClaudeGlobalConfig {
    param(
        [Parameter(Mandatory)]
        [string]$StartupRoot,
        [Parameter(Mandatory)]
        [string]$ProjectDir
    )

    $claudeTemplatePath = Join-Path $StartupRoot 'Claude\templates\claude\CLAUDE.md'
    if (-not (Test-Path $claudeTemplatePath)) {
        $claudeTemplatePath = Join-Path $StartupRoot 'scripts\templates\CLAUDE.md'
    }

    Sync-ProjectTemplate `
        -TemplatePath $claudeTemplatePath `
        -TargetPath (Join-Path $ProjectDir 'CLAUDE.md') `
        -Label 'CLAUDE.md'

    # v3.2.45: Claude/templates/claudeos/ を .claude/claudeos/ の正本として一本化
    # (scripts/templates/claudeos/ は削除済み、fallback も廃止)
    Sync-ProjectTemplateDirectory `
        -TemplateDir (Join-Path $StartupRoot 'Claude\templates\claudeos') `
        -TargetDir (Join-Path $ProjectDir '.claude\claudeos') `
        -Label '.claude/claudeos'

    # v3.2.49 (E-1): Agent Teams を runtime 有効化。
    # Claude Code は .claude/agents/ のみを自動 discovery するため、
    # .claude/claudeos/agents/ とは別に標準 path にも同期する。
    Sync-ProjectTemplateDirectory `
        -TemplateDir (Join-Path $StartupRoot 'Claude\templates\claudeos\agents') `
        -TargetDir (Join-Path $ProjectDir '.claude\agents') `
        -Label '.claude/agents'

    # v3.2.50 (E-2): slash commands を runtime 有効化 (39 ファイル)
    Sync-ProjectTemplateDirectory `
        -TemplateDir (Join-Path $StartupRoot 'Claude\templates\claudeos\commands') `
        -TargetDir (Join-Path $ProjectDir '.claude\commands') `
        -Label '.claude/commands'

    # v3.2.51 (E-3): skills を runtime 有効化 (64 skill ディレクトリ)
    Sync-ProjectTemplateDirectory `
        -TemplateDir (Join-Path $StartupRoot 'Claude\templates\claudeos\skills') `
        -TargetDir (Join-Path $ProjectDir '.claude\skills') `
        -Label '.claude/skills'

    # v3.2.52 (E-4): hooks 定義と hook scripts を .claude/ に配置。
    # 注: 現状 hook scripts は stub (console.log のみ)。完全な runtime 有効化には
    # (1) 実装を詰める、(2) settings.json の hooks セクションで登録、の両方が必要。
    # 本 PR ではファイル配置までを担当し、runtime 登録は settings.json 統合 (F) 側で扱う。
    Sync-ProjectTemplateDirectory `
        -TemplateDir (Join-Path $StartupRoot 'Claude\templates\claudeos\hooks') `
        -TargetDir (Join-Path $ProjectDir '.claude\hooks') `
        -Label '.claude/hooks'

    # v3.2.53 (F): settings.json は Claude/templates/claude/settings.json に一本化
    $settingsTemplatePath = Join-Path $StartupRoot 'Claude\templates\claude\settings.json'
    Initialize-ProjectTemplate `
        -TemplatePath $settingsTemplatePath `
        -TargetPath (Join-Path $ProjectDir '.claude\settings.json') `
        -Label '.claude/settings.json' `
        -EnsureParentDirectory

    Initialize-ProjectTemplate `
        -TemplatePath (Join-Path $StartupRoot 'scripts\templates\claude-mcp.json') `
        -TargetPath (Join-Path $ProjectDir '.mcp.json') `
        -Label '.mcp.json'

    Sync-ProjectTemplate `
        -TemplatePath (Join-Path $StartupRoot 'scripts\templates\claude-statusline.py') `
        -TargetPath (Join-Path $ProjectDir '.claude\statusline.py') `
        -Label '.claude/statusline.py' `
        -EnsureParentDirectory
}

<#
.SYNOPSIS
    Syncs Codex global config templates (AGENTS.md, .codex/config.toml) into the project directory.
#>
function Sync-LauncherCodexGlobalConfig {
    param(
        [Parameter(Mandatory)]
        [string]$StartupRoot,
        [Parameter(Mandatory)]
        [string]$ProjectDir
    )

    $agentsTemplatePath = Join-Path $StartupRoot 'Codex\AGENTS.md'
    if (-not (Test-Path $agentsTemplatePath)) {
        $agentsTemplatePath = Join-Path $StartupRoot 'scripts\templates\AGENTS.md'
    }

    Sync-ProjectTemplate `
        -TemplatePath $agentsTemplatePath `
        -TargetPath (Join-Path $ProjectDir 'AGENTS.md') `
        -Label 'AGENTS.md'

    Initialize-ProjectTemplate `
        -TemplatePath (Join-Path $StartupRoot 'scripts\templates\codex-config.toml') `
        -TargetPath (Join-Path $ProjectDir '.codex\config.toml') `
        -Label '.codex/config.toml' `
        -EnsureParentDirectory
}

<#
.SYNOPSIS
    Syncs Copilot global config templates (copilot-instructions.md, .github/mcp.json) into the project directory.
#>
function Sync-LauncherCopilotGlobalConfig {
    param(
        [Parameter(Mandatory)]
        [string]$StartupRoot,
        [Parameter(Mandatory)]
        [string]$ProjectDir
    )

    $copilotTemplatePath = Join-Path $StartupRoot 'CopilotCLI\AGENTS.md'
    if (-not (Test-Path $copilotTemplatePath)) {
        $copilotTemplatePath = Join-Path $StartupRoot 'scripts\templates\copilot-instructions.md'
    }

    Sync-ProjectTemplate `
        -TemplatePath $copilotTemplatePath `
        -TargetPath (Join-Path $ProjectDir '.github\copilot-instructions.md') `
        -Label 'copilot-instructions.md' `
        -EnsureParentDirectory

    Initialize-ProjectTemplate `
        -TemplatePath (Join-Path $StartupRoot 'scripts\templates\copilot-mcp.json') `
        -TargetPath (Join-Path $ProjectDir '.github\mcp.json') `
        -Label '.github/mcp.json' `
        -EnsureParentDirectory
}

<#
.SYNOPSIS
    Generates a Bash script fragment that deploys a template file to a remote target path via base64 encoding.
#>
function New-RemoteTemplateDeployScript {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Factory function returns in-memory object; no persistent system state is modified')]
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,
        [Parameter(Mandatory)]
        [string]$TargetPath,
        [Parameter(Mandatory)]
        [string]$Label,
        [switch]$EnsureParentDirectory
    )

    if (-not (Test-Path $TemplatePath)) {
        return ""
    }

    $content = Get-Content $TemplatePath -Raw -Encoding UTF8
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
    $normalizedTargetPath = $TargetPath.Replace('\', '/')
    $mkdir = ""
    if ($EnsureParentDirectory) {
        $mkdir = "mkdir -p `"`$(dirname `"$normalizedTargetPath`")`"`n"
    }

    return @"
$mkdir
TMP_FILE=`$(mktemp)
printf '%s' '$base64' | base64 -d > "`$TMP_FILE"
if [ ! -f "$normalizedTargetPath" ] || ! cmp -s "`$TMP_FILE" "$normalizedTargetPath"; then
  mv "`$TMP_FILE" "$normalizedTargetPath"
  echo "[OK] $Label を配置/更新しました: $normalizedTargetPath"
else
  rm -f "`$TMP_FILE"
  echo "[INFO] $Label は最新です: $normalizedTargetPath"
fi
"@
}
