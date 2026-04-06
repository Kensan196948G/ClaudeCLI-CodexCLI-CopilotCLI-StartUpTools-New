# ============================================================
# McpHealthCheck.psm1 - MCP server health check module
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.7.0
# ============================================================

Set-StrictMode -Version Latest

function ConvertTo-McpProcessArgumentString {
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

function Invoke-McpProcessWithTimeout {
    param(
        [string]$Command,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 5
    )

    $stdoutPath = Join-Path $env:TEMP ("ai-startup-mcp-" + [guid]::NewGuid().ToString() + ".out")
    $stderrPath = Join-Path $env:TEMP ("ai-startup-mcp-" + [guid]::NewGuid().ToString() + ".err")
    $process = $null
    try {
        $resolved = Get-Command $Command -ErrorAction Stop
        $filePath = if ($resolved.Source) { $resolved.Source } else { $Command }
        $process = Start-Process -FilePath $filePath -ArgumentList (ConvertTo-McpProcessArgumentString -Arguments $Arguments) -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if ($process.WaitForExit($TimeoutSec * 1000)) {
            $stdout = if (Test-Path $stdoutPath) { Get-Content -Path $stdoutPath -Raw -Encoding UTF8 } else { '' }
            $stderr = if (Test-Path $stderrPath) { Get-Content -Path $stderrPath -Raw -Encoding UTF8 } else { '' }
            return [pscustomobject]@{
                TimedOut  = $false
                ExitCode  = $process.ExitCode
                Output    = ($stdout + $stderr).Trim()
            }
        }

        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            TimedOut  = $true
            ExitCode  = -1
            Output    = "health command timed out after ${TimeoutSec}s"
        }
    }
    finally {
        foreach ($path in @($stdoutPath, $stderrPath)) {
            Remove-Item $path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-McpCommandExists {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-McpServerHealth {
    param(
        [string]$Name,
        [object]$Definition
    )

    $command = if ($Definition.PSObject.Properties.Name -contains 'command' -and $Definition.command) { "$($Definition.command)" } else { '' }
    $commandExists = if ($command) { Test-McpCommandExists -Command $command } else { $false }
    $cmdArgs = if ($Definition.PSObject.Properties.Name -contains 'args' -and $null -ne $Definition.args) { @($Definition.args | ForEach-Object { "$_" }) } else { @() }
    $startupCommand = if ($Definition.PSObject.Properties.Name -contains 'startupCommand' -and $null -ne $Definition.startupCommand) { @($Definition.startupCommand | ForEach-Object { "$_" }) } else { @() }
    $shutdownCommand = if ($Definition.PSObject.Properties.Name -contains 'shutdownCommand' -and $null -ne $Definition.shutdownCommand) { @($Definition.shutdownCommand | ForEach-Object { "$_" }) } else { @() }
    $healthCommand = if ($Definition.PSObject.Properties.Name -contains 'healthCommand' -and $null -ne $Definition.healthCommand) { @($Definition.healthCommand | ForEach-Object { "$_" }) } else { @() }
    $healthStatus = 'not_configured'
    $healthOutput = $null
    $serverStatus = if ($commandExists) { 'available' } else { 'unavailable' }
    $runtimeProbeEnabled = ($env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE -eq '1')
    $healthTimeoutSec = if ($Definition.PSObject.Properties.Name -contains 'healthCommandTimeoutSec' -and $null -ne $Definition.healthCommandTimeoutSec) {
        [int]$Definition.healthCommandTimeoutSec
    }
    elseif ($env:AI_STARTUP_MCP_HEALTH_TIMEOUT_SEC) {
        [int]$env:AI_STARTUP_MCP_HEALTH_TIMEOUT_SEC
    }
    else {
        5
    }
    $startupTimeoutSec = if ($Definition.PSObject.Properties.Name -contains 'startupCommandTimeoutSec' -and $null -ne $Definition.startupCommandTimeoutSec) {
        [int]$Definition.startupCommandTimeoutSec
    }
    elseif ($env:AI_STARTUP_MCP_STARTUP_TIMEOUT_SEC) {
        [int]$env:AI_STARTUP_MCP_STARTUP_TIMEOUT_SEC
    }
    else {
        10
    }
    $shutdownTimeoutSec = if ($Definition.PSObject.Properties.Name -contains 'shutdownCommandTimeoutSec' -and $null -ne $Definition.shutdownCommandTimeoutSec) {
        [int]$Definition.shutdownCommandTimeoutSec
    }
    elseif ($env:AI_STARTUP_MCP_SHUTDOWN_TIMEOUT_SEC) {
        [int]$env:AI_STARTUP_MCP_SHUTDOWN_TIMEOUT_SEC
    }
    else {
        10
    }
    $startupStatus = 'not_requested'
    $startupOutput = $null
    $shutdownStatus = 'not_requested'
    $shutdownOutput = $null

    if ($runtimeProbeEnabled -and @($startupCommand).Count -gt 0) {
        $startupExe = $startupCommand[0]
        if (Test-McpCommandExists -Command $startupExe) {
            try {
                $startupResult = Invoke-McpProcessWithTimeout -Command $startupExe -Arguments @($startupCommand | Select-Object -Skip 1) -TimeoutSec $startupTimeoutSec
                $startupOutput = $startupResult.Output
                if ($startupResult.TimedOut) {
                    $startupStatus = 'timeout'
                }
                else {
                    $startupStatus = if ($startupResult.ExitCode -eq 0) { 'started' } else { 'failed' }
                }
            }
            catch {
                $startupStatus = 'failed'
                $startupOutput = $_.Exception.Message
            }
        }
        else {
            $startupStatus = 'command_unavailable'
        }
    }

    if (@($healthCommand).Count -gt 0) {
        $healthExe = $healthCommand[0]
        if (Test-McpCommandExists -Command $healthExe) {
            try {
                $healthResult = Invoke-McpProcessWithTimeout -Command $healthExe -Arguments @($healthCommand | Select-Object -Skip 1) -TimeoutSec $healthTimeoutSec
                $healthOutput = $healthResult.Output
                if ($healthResult.TimedOut) {
                    $healthStatus = 'timeout'
                }
                else {
                    $healthStatus = if ($healthResult.ExitCode -eq 0) { 'healthy' } else { 'unhealthy' }
                }
            }
            catch {
                $healthStatus = 'unhealthy'
                $healthOutput = $_.Exception.Message
            }
        }
        else {
            $healthStatus = 'health_command_unavailable'
        }
    }

    if ($runtimeProbeEnabled -and @($shutdownCommand).Count -gt 0) {
        $shutdownExe = $shutdownCommand[0]
        if (Test-McpCommandExists -Command $shutdownExe) {
            try {
                $shutdownResult = Invoke-McpProcessWithTimeout -Command $shutdownExe -Arguments @($shutdownCommand | Select-Object -Skip 1) -TimeoutSec $shutdownTimeoutSec
                $shutdownOutput = $shutdownResult.Output
                if ($shutdownResult.TimedOut) {
                    $shutdownStatus = 'timeout'
                }
                else {
                    $shutdownStatus = if ($shutdownResult.ExitCode -eq 0) { 'stopped' } else { 'failed' }
                }
            }
            catch {
                $shutdownStatus = 'failed'
                $shutdownOutput = $_.Exception.Message
            }
        }
        else {
            $shutdownStatus = 'command_unavailable'
        }
    }

    return [pscustomobject]@{
        name                     = $Name
        command                  = $command
        args                     = @($cmdArgs)
        configured               = $true
        commandExists            = $commandExists
        startupCommand           = @($startupCommand)
        startupCommandTimeoutSec = $startupTimeoutSec
        shutdownCommand          = @($shutdownCommand)
        shutdownCommandTimeoutSec = $shutdownTimeoutSec
        healthCommand            = @($healthCommand)
        healthCommandTimeoutSec  = $healthTimeoutSec
        healthStatus             = $healthStatus
        healthOutput             = $healthOutput
        startupStatus            = $startupStatus
        startupOutput            = $startupOutput
        shutdownStatus           = $shutdownStatus
        shutdownOutput           = $shutdownOutput
        status                   = $serverStatus
        kind                     = if ($Name -match 'memory') { 'memory' } else { 'external' }
        operatingProcedure       = [pscustomobject]@{
            startup            = if (@($startupCommand).Count -gt 0) { $startupCommand -join ' ' } else { $null }
            health             = if (@($healthCommand).Count -gt 0) { $healthCommand -join ' ' } else { $null }
            shutdown           = if (@($shutdownCommand).Count -gt 0) { $shutdownCommand -join ' ' } else { $null }
            startupTimeoutSec  = $startupTimeoutSec
            healthTimeoutSec   = $healthTimeoutSec
            shutdownTimeoutSec = $shutdownTimeoutSec
        }
        note = if ($commandExists) { 'command detected' } else { 'command not found or runtime unavailable' }
    }
}

function Get-McpHealthReport {
    param([string]$ProjectRoot)

    $runtimeProbeEnabled = ($env:AI_STARTUP_ENABLE_MCP_RUNTIME_PROBE -eq '1')
    $configPath = if ($env:AI_STARTUP_MCP_CONFIG_PATH) {
        $env:AI_STARTUP_MCP_CONFIG_PATH
    }
    else {
        Join-Path $ProjectRoot '.mcp.json'
    }

    $report = [ordered]@{
        configured  = $false
        configPath  = $configPath
        servers     = @()
        connections = @()
        summary     = 'MCP 設定なし'
    }

    if (-not (Test-Path $configPath)) {
        return [pscustomobject]$report
    }

    try {
        $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $report.configured = $true

        if ($null -eq $config -or $null -eq $config.mcpServers) {
            $report.summary = 'MCP 設定あり: server 定義なし'
            return [pscustomobject]$report
        }

        foreach ($serverProperty in @($config.mcpServers.PSObject.Properties)) {
            $server = Get-McpServerHealth -Name $serverProperty.Name -Definition $serverProperty.Value
            $report.servers += $server
            $report.connections += [pscustomobject]@{
                name               = $server.name
                kind               = $server.kind
                connected          = ($server.healthStatus -eq 'healthy')
                status             = $server.healthStatus
                output             = $server.healthOutput
                operatingProcedure = $server.operatingProcedure
                runtimeProbe       = [pscustomobject]@{
                    enabled        = $runtimeProbeEnabled
                    startupStatus  = $server.startupStatus
                    startupOutput  = $server.startupOutput
                    shutdownStatus = $server.shutdownStatus
                    shutdownOutput = $server.shutdownOutput
                }
            }
        }

        if (@($report.servers).Count -gt 0) {
            $report.summary = "MCP 設定あり: $(@($report.servers).Count) server(s)"
        }
        else {
            $report.summary = 'MCP 設定あり: server 定義なし'
        }
    }
    catch {
        $report.summary = "MCP 設定の解析に失敗: $($_.Exception.Message)"
    }

    return [pscustomobject]$report
}

function Show-McpHealthReport {
    param([pscustomobject]$Report)

    function Write-McpInfo { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
    function Write-McpOk   { param([string]$Message) Write-Host "[ OK ] $Message" -ForegroundColor Green }
    function Write-McpWarn  { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
    function Write-McpFail  { param([string]$Message) Write-Host "[FAIL] $Message" -ForegroundColor Red }

    Write-Host ''
    Write-Host '=== MCP Health Check ===' -ForegroundColor Magenta
    Write-Host ''

    if (-not $Report.configured) {
        Write-McpWarn $Report.summary
        Write-Host ''
        return
    }

    Write-McpInfo "Config: $($Report.configPath)"
    Write-Host ''

    $availableCount = 0
    $totalCount = @($Report.servers).Count

    foreach ($server in @($Report.servers)) {
        $line = "$($server.name): $($server.command) [$($server.status)] health=$($server.healthStatus)"
        if ($server.status -eq 'available') {
            Write-McpOk $line
            $availableCount++
        }
        else {
            Write-McpFail $line
        }
        if ($server.startupCommand.Count -gt 0) {
            Write-Host "    startup: $($server.operatingProcedure.startup) timeout=$($server.startupCommandTimeoutSec)s" -ForegroundColor DarkGray
        }
        if ($server.shutdownCommand.Count -gt 0) {
            Write-Host "    shutdown: $($server.operatingProcedure.shutdown) timeout=$($server.shutdownCommandTimeoutSec)s" -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Host "=== Summary: $availableCount / $totalCount servers available ===" -ForegroundColor Magenta
    if ($availableCount -eq $totalCount) {
        Write-McpOk 'All MCP servers available'
    }
    else {
        Write-McpWarn "$($totalCount - $availableCount) server(s) unavailable"
    }
    Write-Host ''
}

function Invoke-McpRuntimeProbe {
    <#
    .SYNOPSIS
        Performs a runtime probe on all configured MCP servers.
    .DESCRIPTION
        Attempts to start each MCP server process and checks if it responds,
        then cleanly shuts down. Returns detailed probe results.
    .PARAMETER ProjectRoot
        Project root directory containing .mcp.json.
    .PARAMETER TimeoutSec
        Timeout for each probe attempt. Default: 10.
    #>
    param(
        [string]$ProjectRoot,
        [int]$TimeoutSec = 10
    )

    $report = Get-McpHealthReport -ProjectRoot $ProjectRoot
    if (-not $report.configured) {
        return [pscustomobject]@{
            Configured = $false
            ProbeResults = @()
            Summary = 'MCP not configured'
        }
    }

    $probeResults = @()
    foreach ($server in @($report.servers)) {
        $probeResult = [ordered]@{
            Name = $server.name
            Command = $server.command
            CommandAvailable = ($server.status -eq 'available')
            RuntimeStatus = 'not_tested'
            StartupTime = $null
            Error = $null
        }

        if ($server.status -ne 'available') {
            $probeResult.RuntimeStatus = 'command_unavailable'
            $probeResults += [pscustomobject]$probeResult
            continue
        }

        # Attempt runtime probe via process start
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-McpProcessWithTimeout -Command $server.command -Arguments $server.startupCommand -TimeoutSec $TimeoutSec
            $sw.Stop()
            $probeResult.StartupTime = "$($sw.ElapsedMilliseconds)ms"

            if ($null -ne $result -and $result.ExitCode -eq 0) {
                $probeResult.RuntimeStatus = 'responsive'
            }
            elseif ($null -ne $result) {
                $probeResult.RuntimeStatus = 'started_with_error'
                $probeResult.Error = "Exit code: $($result.ExitCode)"
            }
            else {
                $probeResult.RuntimeStatus = 'timeout'
            }
        }
        catch {
            $probeResult.RuntimeStatus = 'probe_failed'
            $probeResult.Error = $_.Exception.Message
        }

        $probeResults += [pscustomobject]$probeResult
    }

    $responsive = @($probeResults | Where-Object { $_.RuntimeStatus -eq 'responsive' }).Count

    return [pscustomobject]@{
        Configured = $true
        ProbeResults = $probeResults
        Summary = "$responsive/$($probeResults.Count) servers probed successfully"
    }
}

function Get-McpQuickStatus {
    <#
    .SYNOPSIS
        Returns a one-line MCP status string for dashboard display.
    #>
    param([string]$ProjectRoot)

    try {
        $report = Get-McpHealthReport -ProjectRoot $ProjectRoot
        if (-not $report.configured) { return 'MCP: not configured' }
        $available = @($report.servers | Where-Object { $_.status -eq 'available' }).Count
        $total = @($report.servers).Count
        $icon = if ($available -eq $total) { 'OK' } else { 'WARN' }
        return "MCP: [$icon] $available/$total servers"
    }
    catch {
        return 'MCP: check failed'
    }
}

Export-ModuleMember -Function @(
    'Get-McpServerHealth',
    'Get-McpHealthReport',
    'Show-McpHealthReport',
    'Test-McpCommandExists',
    'Invoke-McpProcessWithTimeout',
    'Invoke-McpRuntimeProbe',
    'Get-McpQuickStatus'
)
