# ============================================================
# ArchitectureCheck.psm1 - Architecture violation detector
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.9.0
# Phase 3: Architecture Check Loop (Issue #49)
# ============================================================

Set-StrictMode -Version Latest

$script:ForbiddenPatterns = @(
    [pscustomobject]@{
        id      = 'DIRECT_PUSH_MAIN'
        name    = 'main直接push禁止'
        pattern = 'git push.*origin main'
        severity = 'CRITICAL'
        message  = 'mainブランチへの直接pushは禁止されています。PRを通してください。'
    }
    [pscustomobject]@{
        id      = 'HARDCODED_SECRET'
        name    = 'ハードコード秘密情報'
        pattern = '(?i)(password|secret|api_key|token)\s*=\s*[''"][^''"]{4,}'
        severity = 'CRITICAL'
        message  = '秘密情報のハードコードが検出されました。環境変数または設定ファイルを使用してください。'
    }
    [pscustomobject]@{
        id      = 'MISSING_STRICT_MODE'
        name    = 'StrictMode未設定'
        pattern = '^(?!.*Set-StrictMode)[\s\S]*$'
        severity = 'WARNING'
        message  = 'Set-StrictMode -Version Latest が設定されていません。'
        fileOnly = $true
        extensions = @('.psm1', '.ps1')
    }
    [pscustomobject]@{
        id      = 'CIRCULAR_IMPORT'
        name    = '循環インポート疑惑'
        pattern = 'Import-Module.*\$PSScriptRoot.*Import-Module.*\$PSScriptRoot'
        severity = 'WARNING'
        message  = '同一スクリプト内で複数のImport-Moduleが検出されました。循環依存の可能性があります。'
    }
    [pscustomobject]@{
        id      = 'MISSING_ERROR_HANDLING'
        name    = 'エラーハンドリング不足'
        pattern = 'Invoke-Expression|iex '
        severity = 'WARNING'
        message  = 'Invoke-Expression の使用が検出されました。セキュリティリスクがあります。'
    }
)

$script:ModuleDependencyRules = @{
    'Start-ClaudeCode.ps1'    = @('LauncherCommon.psm1', 'Config.psm1')
    'Start-CodexCLI.ps1'      = @('LauncherCommon.psm1', 'Config.psm1')
    'Start-CopilotCLI.ps1'    = @('LauncherCommon.psm1', 'Config.psm1')
    'Start-Menu.ps1'           = @('LauncherCommon.psm1', 'Config.psm1', 'MenuCommon.psm1')
    'Test-AllTools.ps1'        = @('Config.psm1', 'LauncherCommon.psm1', 'McpHealthCheck.psm1')
}

function Get-ProjectRoot {
    $path = $PSScriptRoot
    while ($path -and -not (Test-Path (Join-Path $path '.git'))) {
        $path = Split-Path $path -Parent
    }
    return $path
}

function Invoke-ArchitectureCheck {
    [CmdletBinding()]
    param(
        [string]$Path = '',
        [string[]]$Extensions = @('.ps1', '.psm1'),
        [switch]$IncludeWarnings
    )

    if (-not $Path) {
        $Path = Get-ProjectRoot
    }
    if (-not $Path -or -not (Test-Path $Path)) {
        throw "プロジェクトルートが見つかりません: $Path"
    }

    $violations = @()
    $checkedFiles = 0

    $files = Get-ChildItem -Path $Path -Recurse -Include ($Extensions | ForEach-Object { "*$_" }) -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\node_modules\\' }

    foreach ($file in $files) {
        $checkedFiles++
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        foreach ($rule in $script:ForbiddenPatterns) {
            if ($rule.PSObject.Properties['fileOnly'] -and $rule.fileOnly) {
                $ext = $file.Extension.ToLower()
                if ($rule.extensions -notcontains $ext) { continue }

                if ($content -notmatch 'Set-StrictMode') {
                    $violations += [pscustomobject]@{
                        RuleId   = $rule.id
                        RuleName = $rule.name
                        Severity = $rule.severity
                        File     = $file.FullName.Replace($Path, '').TrimStart('\')
                        Line     = 0
                        Message  = $rule.message
                    }
                }
                continue
            }

            $lines = $content -split "`n"
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match $rule.pattern) {
                    $violations += [pscustomobject]@{
                        RuleId   = $rule.id
                        RuleName = $rule.name
                        Severity = $rule.severity
                        File     = $file.FullName.Replace($Path, '').TrimStart('\')
                        Line     = $i + 1
                        Message  = $rule.message
                    }
                }
            }
        }
    }

    $criticalCount = @($violations | Where-Object { $_.Severity -eq 'CRITICAL' }).Count
    $warningCount  = @($violations | Where-Object { $_.Severity -eq 'WARNING' }).Count

    $result = [pscustomobject]@{
        CheckedFiles    = $checkedFiles
        TotalViolations = $violations.Count
        CriticalCount   = $criticalCount
        WarningCount    = $warningCount
        Violations      = $violations
        Passed          = ($criticalCount -eq 0)
        Timestamp       = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    }

    return $result
}

function Get-ArchitectureViolation {
    [CmdletBinding()]
    param(
        [string]$Path = '',
        [ValidateSet('CRITICAL', 'WARNING', 'ALL')]
        [string]$Severity = 'ALL'
    )

    $result = Invoke-ArchitectureCheck -Path $Path -IncludeWarnings

    $violations = switch ($Severity) {
        'CRITICAL' { $result.Violations | Where-Object { $_.Severity -eq 'CRITICAL' } }
        'WARNING'  { $result.Violations | Where-Object { $_.Severity -eq 'WARNING' } }
        'ALL'      { $result.Violations }
    }

    return $violations
}

function Show-ArchitectureCheckReport {
    [CmdletBinding()]
    param(
        [string]$Path = ''
    )

    $result = Invoke-ArchitectureCheck -Path $Path -IncludeWarnings

    Write-Host ""
    Write-Host "=== Architecture Check Report ===" -ForegroundColor Cyan
    Write-Host "チェックファイル数: $($result.CheckedFiles)"
    Write-Host "違反総数: $($result.TotalViolations) (CRITICAL: $($result.CriticalCount), WARNING: $($result.WarningCount))"
    Write-Host ""

    if ($result.Violations.Count -eq 0) {
        Write-Host "[ OK ] アーキテクチャ違反なし" -ForegroundColor Green
    } else {
        foreach ($v in ($result.Violations | Sort-Object Severity, File)) {
            $color = if ($v.Severity -eq 'CRITICAL') { 'Red' } else { 'Yellow' }
            $lineInfo = if ($v.Line -gt 0) { ":$($v.Line)" } else { '' }
            Write-Host "[$($v.Severity)] $($v.File)$lineInfo" -ForegroundColor $color
            Write-Host "  Rule: $($v.RuleName)" -ForegroundColor $color
            Write-Host "  $($v.Message)"
        }
    }

    Write-Host ""
    if ($result.Passed) {
        Write-Host "[ PASS ] Architecture Check PASSED" -ForegroundColor Green
    } else {
        Write-Host "[ FAIL ] Architecture Check FAILED ($($result.CriticalCount) critical violation(s))" -ForegroundColor Red
    }

    return $result
}

function Test-ModuleDependency {
    [CmdletBinding()]
    param(
        [string]$Path = ''
    )

    if (-not $Path) { $Path = Get-ProjectRoot }

    $results = @()

    foreach ($script in $script:ModuleDependencyRules.Keys) {
        $scriptPath = Get-ChildItem -Path $Path -Recurse -Filter $script -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $scriptPath) { continue }

        $content = Get-Content $scriptPath.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        $requiredModules = $script:ModuleDependencyRules[$script]
        foreach ($module in $requiredModules) {
            $found = $content -match [regex]::Escape($module)
            $results += [pscustomobject]@{
                Script   = $script
                Module   = $module
                Found    = $found
                Status   = if ($found) { 'OK' } else { 'MISSING' }
            }
        }
    }

    return $results
}

Export-ModuleMember -Function @(
    'Invoke-ArchitectureCheck'
    'Get-ArchitectureViolation'
    'Show-ArchitectureCheckReport'
    'Test-ModuleDependency'
)
