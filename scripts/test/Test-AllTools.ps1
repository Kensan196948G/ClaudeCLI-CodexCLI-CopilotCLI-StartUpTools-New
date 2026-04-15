<#
.SYNOPSIS
    Diagnostics script for AI CLI startup tools.
.DESCRIPTION
    Checks configuration, command availability, auth prerequisites,
    MCP definitions, paths, and launch examples.
#>

param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:DiagnosticsSchemaVersion = '1.0.0'
$script:StartupRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:DiagnosticsSchemaPath = Join-Path $script:StartupRoot 'docs\common\schemas\test-all-tools-report.schema.json'

Import-Module (Join-Path $script:StartupRoot 'scripts\lib\Config.psm1') -Force
Import-Module (Join-Path $script:StartupRoot 'scripts\lib\LauncherCommon.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $script:StartupRoot 'scripts\lib\McpHealthCheck.psm1') -Force

function Test-CommandExists {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-CommandVersionLine {
    param(
        [string]$Command,
        [string[]]$CmdArgs = @()
    )

    try {
        $output = & $Command @CmdArgs 2>&1 | Select-Object -First 1
        if ($null -ne $output) {
            return "$output".Trim()
        }
    }
    catch {
    }

    return $null
}

function Mask-SecretTail {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return '未設定'
    }
    if ($Value.Length -le 4) {
        return '****'
    }

    return '****' + $Value.Substring($Value.Length - 4)
}

function Get-AllToolsReportSchemaDocument {
    if (-not (Test-Path $script:DiagnosticsSchemaPath)) {
        return $null
    }

    return Get-Content -Path $script:DiagnosticsSchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-ProcessArgumentString {
    param([string[]]$Arguments = @())

    return (
        @($Arguments | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + ($_.Replace('"', '\"')) + '"'
            }
            else {
                "$_"
            }
        }) -join ' '
    )
}

function Invoke-ProcessWithTimeout {
    param(
        [string]$Command,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 5
    )

    $stdoutPath = Join-Path $env:TEMP ("ai-startup-health-" + [guid]::NewGuid().ToString() + ".out")
    $stderrPath = Join-Path $env:TEMP ("ai-startup-health-" + [guid]::NewGuid().ToString() + ".err")
    $process = $null
    try {
        $resolved = Get-Command $Command -ErrorAction Stop
        $filePath = if ($resolved.Source) { $resolved.Source } else { $Command }
        $process = Start-Process -FilePath $filePath -ArgumentList (ConvertTo-ProcessArgumentString -Arguments $Arguments) -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if ($process.WaitForExit($TimeoutSec * 1000)) {
            $stdout = if (Test-Path $stdoutPath) { Get-Content -Path $stdoutPath -Raw -Encoding UTF8 } else { '' }
            $stderr = if (Test-Path $stderrPath) { Get-Content -Path $stderrPath -Raw -Encoding UTF8 } else { '' }
            return [pscustomobject]@{
                TimedOut = $false
                ExitCode = $process.ExitCode
                Output = ($stdout + $stderr).Trim()
            }
        }

        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            TimedOut = $true
            ExitCode = -1
            Output = "health command timed out after ${TimeoutSec}s"
        }
    }
    finally {
        foreach ($path in @($stdoutPath, $stderrPath)) {
            Remove-Item $path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-McpServerDiagnostics {
    param(
        [string]$Name,
        [object]$Definition
    )
    return Get-McpServerHealth -Name $Name -Definition $Definition
}

function Get-McpDiagnostics {
    param([string]$ProjectRoot)
    return Get-McpHealthReport -ProjectRoot $ProjectRoot
}

function Get-AllToolsDiagnostics {
    param([string]$ConfigPath)

    $report = [ordered]@{
        schemaVersion = $script:DiagnosticsSchemaVersion
        configPath = $ConfigPath
        configExists = $false
        configValid = $false
        schemaValid = $false
        errors = @()
        common = @()
        tools = @()
        mcp = [pscustomobject]@{
            configured = $false
            configPath = ''
            servers = @()
            connections = @()
            summary = 'MCP 設定なし'
        }
        paths = @()
        examples = @(
            '.\scripts\main\Start-ClaudeCode.ps1 -Project <name> -Local -DryRun',
            '.\scripts\main\Start-CodexCLI.ps1 -Project <name> -DryRun',
            '.\scripts\main\Start-CopilotCLI.ps1 -Project <name> -Local -DryRun'
        )
        summary = [pscustomobject]@{
            ok = $true
            message = '主要チェックをパスしました。'
        }
    }

    $config = $null
    if (Test-Path $ConfigPath) {
        $report.configExists = $true
        try {
            $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.configValid = $true
            [void](Assert-StartupConfigSchema -ConfigPath $ConfigPath)
            $report.schemaValid = $true
        }
        catch {
            $report.errors += "config.json validation error: $($_.Exception.Message)"
            $report.summary.ok = $false
        }
    }
    else {
        $report.errors += "config.json not found: $ConfigPath"
        $report.summary.ok = $false
    }

    foreach ($entry in @(
        @{ name = 'node'; label = 'Node.js'; args = @('--version'); install = 'winget install OpenJS.NodeJS' },
        @{ name = 'npm'; label = 'npm'; args = @('--version'); install = '' },
        @{ name = 'git'; label = 'Git'; args = @('--version'); install = 'winget install Git.Git' },
        @{ name = 'gh'; label = 'GitHub CLI'; args = @('--version'); install = 'winget install GitHub.cli' },
        @{ name = 'ssh'; label = 'SSH client'; args = @('-V'); install = 'Enable OpenSSH Client' }
    )) {
        $exists = Test-CommandExists -Command $entry.name
        $report.common += [pscustomobject]@{
            name = $entry.name
            label = $entry.label
            exists = $exists
            version = if ($exists) { Get-CommandVersionLine -Command $entry.name -CmdArgs $entry.args } else { $null }
            install = $entry.install
        }
    }

    $report.mcp = Get-McpDiagnostics -ProjectRoot $script:StartupRoot
    if ($report.mcp.configured -and @($report.mcp.servers | Where-Object { $_.status -eq 'unavailable' }).Count -gt 0) {
        $report.summary.ok = $false
    }

    if ($null -ne $config) {
        foreach ($tool in @(
            @{
                id = 'claude'
                label = 'Claude Code'
                command = 'claude'
                versionArgs = @('--version')
                install = $config.tools.claude.installCommand
                authEnv = 'ANTHROPIC_API_KEY'
                authHint = 'Use /login after starting Claude Code, or set ANTHROPIC_API_KEY.'
            },
            @{
                id = 'codex'
                label = 'Codex CLI'
                command = 'codex'
                versionArgs = @('--version')
                install = $config.tools.codex.installCommand
                authEnv = 'OPENAI_API_KEY'
                authHint = 'Use codex --login, or set OPENAI_API_KEY.'
            }
        )) {
            $exists = Test-CommandExists -Command $tool.command
            if (-not $exists) {
                $report.summary.ok = $false
            }

            $secret = [Environment]::GetEnvironmentVariable($tool.authEnv)
            $report.tools += [pscustomobject]@{
                id = $tool.id
                label = $tool.label
                command = $tool.command
                exists = $exists
                version = if ($exists) { Get-CommandVersionLine -Command $tool.command -CmdArgs $tool.versionArgs } else { $null }
                install = $tool.install
                authEnv = $tool.authEnv
                authConfigured = [bool]$secret
                authDisplay = if ($secret) { Mask-SecretTail -Value $secret } else { '未設定' }
                authHint = $tool.authHint
            }
        }

        $copilotCommand = if ($config.tools.copilot.command) { "$($config.tools.copilot.command)" } else { 'copilot' }
        $copilotVersionArgs = if ($config.tools.copilot.checkCommand -and $config.tools.copilot.checkCommand -match '--version') { @('--version') } else { @('--version') }
        $copilotVersion = if (Test-CommandExists -Command $copilotCommand) { Get-CommandVersionLine -Command $copilotCommand -CmdArgs $copilotVersionArgs } else { $null }
        if (-not $copilotVersion) {
            $report.summary.ok = $false
        }
        $report.tools += [pscustomobject]@{
            id = 'copilot'
            label = 'GitHub Copilot CLI'
            command = "$copilotCommand $($config.tools.copilot.args -join ' ')".Trim()
            exists = [bool]$copilotVersion
            version = $copilotVersion
            install = $config.tools.copilot.installCommand
            authEnv = ''
            authConfigured = $true
            authDisplay = '起動時に対話認証または既存セッションを使用'
            authHint = 'copilot login または初回起動時の認証'
        }

        foreach ($pathInfo in @(
            @{ id = 'projectsDir'; label = 'Local projectsDir'; path = $config.projectsDir },
            @{ id = 'sshProjectsDir'; label = 'SSH projectsDir'; path = $config.sshProjectsDir },
            @{ id = 'projectsDirUnc'; label = 'UNC path'; path = $config.projectsDirUnc }
        )) {
            $exists = if ($pathInfo.path) { Test-Path $pathInfo.path } else { $false }
            if (($pathInfo.id -ne 'projectsDirUnc') -and -not $exists) {
                $report.summary.ok = $false
            }
            $report.paths += [pscustomobject]@{
                id = $pathInfo.id
                label = $pathInfo.label
                path = $pathInfo.path
                exists = $exists
                projectCount = if ($exists -and $pathInfo.id -ne 'projectsDirUnc') { @(Get-ChildItem -Path $pathInfo.path -Directory -ErrorAction SilentlyContinue).Count } else { 0 }
            }
        }
    }

    if (-not $report.summary.ok) {
        $report.summary.message = '一部のチェックに問題があります。'
    }

    return [pscustomobject]$report
}

function Test-AllToolsReportSchema {
    param([pscustomobject]$Report)

    $errors = [System.Collections.Generic.List[string]]::new()
    $schema = Get-AllToolsReportSchemaDocument
    $requiredFields = if ($schema) { @($schema.required) } else { @('schemaVersion', 'configPath', 'configExists', 'configValid', 'schemaValid', 'errors', 'common', 'tools', 'mcp', 'paths', 'examples', 'summary') }
    foreach ($field in $requiredFields) {
        if (-not ($Report.PSObject.Properties.Name -contains $field)) {
            $errors.Add("missing top-level field: $field")
        }
    }

    $expectedVersion = if ($schema -and $schema.schemaVersion) { "$($schema.schemaVersion)" } else { $script:DiagnosticsSchemaVersion }
    if (($Report.PSObject.Properties.Name -contains 'schemaVersion') -and $Report.schemaVersion -ne $expectedVersion) {
        $errors.Add("invalid schemaVersion: $($Report.schemaVersion)")
    }

    foreach ($tool in @($Report.tools)) {
        foreach ($field in @('id', 'label', 'command', 'exists', 'install', 'authConfigured', 'authDisplay', 'authHint')) {
            if (-not ($tool.PSObject.Properties.Name -contains $field)) {
                $errors.Add("missing tools field: $field")
            }
        }
    }

    foreach ($pathItem in @($Report.paths)) {
        foreach ($field in @('id', 'label', 'path', 'exists', 'projectCount')) {
            if (-not ($pathItem.PSObject.Properties.Name -contains $field)) {
                $errors.Add("missing paths field: $field")
            }
        }
    }

    $mcpRequired = if ($schema -and $schema.mcpRequired) { @($schema.mcpRequired) } else { @('configured', 'configPath', 'servers', 'connections', 'summary') }
    foreach ($field in $mcpRequired) {
        if (-not ($Report.mcp.PSObject.Properties.Name -contains $field)) {
            $errors.Add("missing mcp field: $field")
        }
    }

    $mcpServerRequired = if ($schema -and $schema.mcpServerRequired) { @($schema.mcpServerRequired) } else { @('name', 'command', 'commandExists', 'startupCommand', 'startupCommandTimeoutSec', 'shutdownCommand', 'shutdownCommandTimeoutSec', 'healthCommand', 'healthStatus', 'status') }
    foreach ($server in @($Report.mcp.servers)) {
        foreach ($field in $mcpServerRequired) {
            if (-not ($server.PSObject.Properties.Name -contains $field)) {
                $errors.Add("missing mcp.servers field: $field")
            }
        }
    }

    $mcpConnectionRequired = if ($schema -and $schema.mcpConnectionRequired) { @($schema.mcpConnectionRequired) } else { @('name', 'kind', 'connected', 'status', 'output', 'operatingProcedure', 'runtimeProbe') }
    foreach ($connection in @($Report.mcp.connections)) {
        foreach ($field in $mcpConnectionRequired) {
            if (-not ($connection.PSObject.Properties.Name -contains $field)) {
                $errors.Add("missing mcp.connections field: $field")
            }
        }
    }

    return @($errors)
}

function Show-AllToolsDiagnostics {
    param([pscustomobject]$Report)

    function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
    function Write-Ok { param([string]$Message) Write-Host "[ OK ] $Message" -ForegroundColor Green }
    function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
    function Write-Fail { param([string]$Message) Write-Host "[FAIL] $Message" -ForegroundColor Red }

    Write-Host ''
    Write-Host '=== AI CLI Diagnostics ===' -ForegroundColor Magenta
    Write-Host "Config: $($Report.configPath)" -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '--- Config ---' -ForegroundColor Yellow
    if ($Report.configExists) { Write-Ok 'config.json exists' } else { Write-Fail 'config.json missing' }
    if ($Report.configValid) { Write-Ok 'config.json parse ok' }
    if ($Report.schemaValid) { Write-Ok 'config.json schema ok' }
    foreach ($errItem in @($Report.errors)) { Write-Fail $errItem }
    Write-Host ''

    Write-Host '--- Common ---' -ForegroundColor Yellow
    foreach ($entry in @($Report.common)) {
        if ($entry.exists) {
            Write-Ok "$($entry.label): $($entry.version)"
        }
        else {
            Write-Warn "$($entry.label) missing"
        }
    }
    Write-Host ''

    foreach ($tool in @($Report.tools)) {
        Write-Host "--- $($tool.label) ---" -ForegroundColor Yellow
        if ($tool.exists) {
            Write-Ok "$($tool.command): $($tool.version)"
        }
        else {
            Write-Warn "$($tool.command) unavailable"
        }
        if ($tool.authEnv) {
            if ($tool.authConfigured) { Write-Ok "$($tool.authEnv): $($tool.authDisplay)" } else { Write-Warn "$($tool.authEnv) not set" }
        }
        else {
            if ($tool.authConfigured) { Write-Ok 'GitHub auth ok' } else { Write-Warn 'GitHub auth required' }
        }
        Write-Host ''
    }

    Write-Host '--- MCP ---' -ForegroundColor Yellow
    if ($Report.mcp.configured) {
        Write-Info "Config: $($Report.mcp.configPath)"
        foreach ($server in @($Report.mcp.servers)) {
            $line = "$($server.name): $($server.command) [$($server.status)] health=$($server.healthStatus)"
            if ($server.status -eq 'available') { Write-Ok $line } else { Write-Warn $line }
            if ($server.startupCommand.Count -gt 0) {
                Write-Host "    startup: $($server.operatingProcedure.startup) timeout=$($server.startupCommandTimeoutSec)s" -ForegroundColor DarkGray
            }
            if ($server.shutdownCommand.Count -gt 0) {
                Write-Host "    shutdown: $($server.operatingProcedure.shutdown) timeout=$($server.shutdownCommandTimeoutSec)s" -ForegroundColor DarkGray
            }
        }
    }
    else {
        Write-Info $Report.mcp.summary
    }
    Write-Host ''

    Write-Host '--- Paths ---' -ForegroundColor Yellow
    foreach ($pathItem in @($Report.paths)) {
        if ($pathItem.exists) {
            Write-Ok "$($pathItem.label): $($pathItem.path)"
        }
        else {
            Write-Warn "$($pathItem.label): $($pathItem.path)"
        }
    }
    Write-Host ''

    Write-Host '--- Examples ---' -ForegroundColor Yellow
    foreach ($example in @($Report.examples)) {
        Write-Host "  $example"
    }
    Write-Host ''

    Write-Host '=== Summary ===' -ForegroundColor Magenta
    if ($Report.summary.ok) { Write-Ok $Report.summary.message } else { Write-Warn $Report.summary.message }
    Write-Host ''
}

if ($MyInvocation.InvocationName -ne '.') {
    $configPath = Get-StartupConfigPath -StartupRoot $script:StartupRoot
    $report = Get-AllToolsDiagnostics -ConfigPath $configPath
    if ($OutputFormat -eq 'Json') {
        $report | ConvertTo-Json -Depth 8
    }
    else {
        Show-AllToolsDiagnostics -Report $report
    }
}
