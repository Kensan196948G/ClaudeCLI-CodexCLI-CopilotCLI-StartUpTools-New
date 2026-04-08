<#
.SYNOPSIS
    共有ドライブ診断スクリプト

.DESCRIPTION
    `sshProjectsDir` と `projectsDirUnc` を基準に、共有ドライブの到達性と
    解決経路を診断します。`-OutputFormat Json` で機械可読出力にも対応します。
#>

param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

$ErrorActionPreference = "Continue"

$RootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $RootDir "scripts\lib\LauncherCommon.psm1") -Force -DisableNameChecking

function Get-DriveMappingConfig {
    param([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) {
        return [pscustomobject]@{
            sshProjectsDir = 'auto'
            projectsDirUnc = $null
            linuxHost = $null
            configFound = $false
        }
    }

    $config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return [pscustomobject]@{
        sshProjectsDir = if ($config.sshProjectsDir) { $config.sshProjectsDir } else { $config.zDrive }
        projectsDirUnc = if ($config.projectsDirUnc) { $config.projectsDirUnc } else { $config.zDriveUncPath }
        linuxHost = $config.linuxHost
        configFound = $true
    }
}

function Get-NetUseLine {
    param([string]$DriveLetter)

    return (net use 2>&1 | Select-String "${DriveLetter}:")
}

function Get-NetUseIssueType {
    param([string]$NetUseLine)

    if ([string]::IsNullOrWhiteSpace($NetUseLine)) {
        return $null
    }

    if ($NetUseLine -match 'logon failure|access is denied|credential|system error 1219') {
        return 'CredentialError'
    }
    if ($NetUseLine -match 'system error 53|network path was not found|name not found|could not be found') {
        return 'NameResolutionFailure'
    }

    return $null
}

function Get-UncHostName {
    param([string]$UncPath)

    if ([string]::IsNullOrWhiteSpace($UncPath)) {
        return $null
    }
    if ($UncPath -match '^\\\\([^\\]+)\\') {
        return $Matches[1]
    }
    return $null
}

function Get-DriveMappingReport {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$ConfigInfo
    )

    $sshDir = if ($ConfigInfo.sshProjectsDir) { $ConfigInfo.sshProjectsDir } else { 'auto' }

    if ($sshDir -eq 'auto') {
        # Auto mode: detect existing mapping or find available letter
        $driveLetter = $null
        if ($ConfigInfo.projectsDirUnc) {
            $existingSmb = Get-SmbMapping -ErrorAction SilentlyContinue |
                Where-Object { $_.RemotePath -eq $ConfigInfo.projectsDirUnc -and $_.Status -eq 'OK' } |
                Select-Object -First 1
            if ($existingSmb) {
                $driveLetter = ($existingSmb.LocalPath -replace ':', '')
            }
        }
        if (-not $driveLetter) {
            $driveLetter = (Find-AvailableDriveLetter)
            if (-not $driveLetter) { $driveLetter = 'P' }
        }
    }
    else {
        $driveLetter = ($sshDir -replace '[:\\]', '').Trim()
        if ([string]::IsNullOrWhiteSpace($driveLetter)) {
            $driveLetter = 'P'
        }
    }

    $drivePath = "${driveLetter}:\"
    $registryPath = "HKCU:\Network\${driveLetter}"
    $report = [ordered]@{
        configFound = $ConfigInfo.configFound
        driveLetter = $driveLetter
        drivePath = $drivePath
        sshProjectsDir = $sshDir
        projectsDirUnc = $ConfigInfo.projectsDirUnc
        directAccess = $false
        directoryCount = 0
        registryRemotePath = $null
        smbRemotePath = $null
        smbStatus = $null
        smbShareName = $null
        smbShareCandidates = @()
        psDriveRoot = $null
        psDriveDisplayRoot = $null
        netUseLine = $null
        netUseIssue = $null
        targetHost = $null
        dnsResolved = $null
        pingReachable = $null
        smbPort445Reachable = $null
        uncAccessible = $false
        uncCandidates = @()
        recommendation = $null
        repairAdvice = @()
        remapCommand = $null
        reconnectCommands = @()
    }

    if (Test-Path $drivePath) {
        $report.directAccess = $true
        $report.directoryCount = @(Get-ChildItem $drivePath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }).Count
    }

    if (Test-Path $registryPath) {
        $remotePath = (Get-ItemProperty $registryPath -ErrorAction SilentlyContinue).RemotePath
        if ($remotePath) {
            $report.registryRemotePath = $remotePath
        }
    }

    $smbMappings = @(Get-SmbMapping -ErrorAction SilentlyContinue)
    $smbMapping = $null
    foreach ($entry in $smbMappings) {
        if ($null -ne $entry -and $entry.LocalPath -eq "${driveLetter}:") {
            $smbMapping = $entry
            break
        }
    }
    if ($smbMapping) {
        $report.smbRemotePath = $smbMapping.RemotePath
        $report.smbStatus = $smbMapping.Status
        if ($smbMapping.RemotePath -match '^\\\\[^\\]+\\([^\\]+)') {
            $report.smbShareName = $Matches[1]
        }
    }

    $psDrive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
    if ($psDrive) {
        $report.psDriveRoot = $psDrive.Root
        $report.psDriveDisplayRoot = $psDrive.DisplayRoot
    }

    $netUseLine = Get-NetUseLine -DriveLetter $driveLetter
    if ($netUseLine) {
        $report.netUseLine = "$netUseLine"
        $report.netUseIssue = Get-NetUseIssueType -NetUseLine $report.netUseLine
    }

    if ($ConfigInfo.projectsDirUnc -and (Test-Path $ConfigInfo.projectsDirUnc)) {
        $report.uncAccessible = $true
    }

    $uncCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($report.registryRemotePath, $report.smbRemotePath, $report.psDriveDisplayRoot, $ConfigInfo.projectsDirUnc)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $uncCandidates.Contains($candidate)) {
            $uncCandidates.Add($candidate)
        }
    }
    $report.uncCandidates = @($uncCandidates)
    $report.smbShareCandidates = @(
        $uncCandidates |
            ForEach-Object {
                if ($_ -match '^\\\\[^\\]+\\([^\\]+)') { $Matches[1] }
            } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
    $report.targetHost = Get-UncHostName -UncPath $(if ($report.uncCandidates.Count -gt 0) { $report.uncCandidates[0] } else { $ConfigInfo.projectsDirUnc })

    if ($report.targetHost) {
        try {
            $dns = Resolve-DnsName -Name $report.targetHost -ErrorAction Stop
            $report.dnsResolved = (@($dns).Count -gt 0)
        }
        catch {
            $report.dnsResolved = $false
        }

        try {
            $report.pingReachable = [bool](Test-Connection -ComputerName $report.targetHost -Count 1 -Quiet -ErrorAction Stop)
        }
        catch {
            $report.pingReachable = $false
        }

        if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
            try {
                $tnc = Test-NetConnection -ComputerName $report.targetHost -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue
                $report.smbPort445Reachable = [bool]$tnc
            }
            catch {
                $report.smbPort445Reachable = $false
            }
        }
    }

    if ($report.directAccess) {
        $report.recommendation = 'DirectAccess'
        $report.repairAdvice = @('現在の共有ドライブは直接利用可能です。追加対応は不要です。')
    }
    elseif ($report.smbStatus -in @('Unavailable', 'Disconnected')) {
        $report.recommendation = 'RemapDisconnectedSmb'
        $report.remapCommand = "Remove-PSDrive -Name $driveLetter -Force -ErrorAction SilentlyContinue; New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root '$($report.uncCandidates[0])' -Persist"
        $report.repairAdvice = @(
            "SMB 状態が $($report.smbStatus) のため、既存マッピングの再作成が必要です。",
            '既存のドライブ割当を削除してから再マッピングしてください。',
            '資格情報キャッシュとネットワーク到達性も確認してください。'
        )
    }
    elseif ($report.netUseIssue -eq 'CredentialError') {
        $report.recommendation = 'CheckCredentials'
        $report.repairAdvice = @(
            '資格情報エラーの可能性があります。',
            'Windows 資格情報マネージャーの既存エントリを見直してください。',
            '必要なら net use /delete と再認証を実行してください。'
        )
        if ($report.uncCandidates.Count -gt 0) {
            $report.remapCommand = "cmd /c `"net use ${driveLetter}: /delete /y && net use ${driveLetter}: $($report.uncCandidates[0]) /persistent:yes`""
        }
    }
    elseif ($report.netUseIssue -eq 'NameResolutionFailure') {
        $report.recommendation = 'CheckNameResolution'
        $report.repairAdvice = @(
            '共有先ホスト名の名前解決に失敗している可能性があります。',
            'DNS / hosts / VPN / SMB 到達性を確認してください。',
            'UNC パスを IP アドレスで試すか、サーバー名を再確認してください。'
        )
    }
    elseif ($report.targetHost -and $report.dnsResolved -eq $false) {
        $report.recommendation = 'CheckDns'
        $report.repairAdvice = @(
            'UNC 先ホストの DNS 解決に失敗しています。',
            'hosts、DNS サフィックス、VPN 接続を確認してください。'
        )
    }
    elseif ($report.targetHost -and $report.pingReachable -eq $false) {
        $report.recommendation = 'CheckNetworkReachability'
        $report.repairAdvice = @(
            '対象ホストへ ping 到達できません。',
            'ネットワーク疎通、FW、SMB サーバー側の状態を確認してください。'
        )
    }
    elseif ($report.targetHost -and $report.smbPort445Reachable -eq $false) {
        $report.recommendation = 'CheckSmbPort445'
        $report.repairAdvice = @(
            'SMB port 445 へ接続できません。',
            'Windows Defender Firewall、VPN、サーバー側 SMB サービスを確認してください。',
            'Test-NetConnection で TCP 445 の疎通を再確認してください。'
        )
    }
    elseif ($report.smbStatus -eq 'OK' -and -not $report.directAccess) {
        $report.recommendation = 'InvestigateClientAccess'
        $report.repairAdvice = @(
            'SMB マッピング自体は OK ですが、ドライブ文字からの直接アクセスに失敗しています。',
            'Explorer の再接続、権限、オフラインファイル、AV の干渉を確認してください。',
            '一時回避として UNC パス利用に切り替えられます。'
        )
        if ($report.uncCandidates.Count -gt 0) {
            $report.remapCommand = "New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root '$($report.uncCandidates[0])' -Persist"
        }
    }
    elseif ($report.uncCandidates.Count -gt 0) {
        $report.recommendation = 'UseUncFallback'
        $report.remapCommand = "New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root '$($report.uncCandidates[0])' -Persist"
        $report.repairAdvice = @(
            '共有ドライブ文字は使えませんが、UNC 経由でアクセスできます。',
            '起動スクリプトは UNC フォールバックで継続できます。',
            '必要なら永続マッピングを再作成してください。'
        )
    }
    else {
        $report.recommendation = 'MissingMapping'
        $report.remapCommand = "New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root '\\\\server\\share' -Persist"
        $report.repairAdvice = @(
            '共有ドライブと UNC の両方が解決できていません。',
            'Windows Explorer または New-PSDrive で再マッピングしてください。',
            'config.json の sshProjectsDir / projectsDirUnc を確認してください。'
        )
    }

    if ($report.uncCandidates.Count -gt 0) {
        $reconnectCommands = [System.Collections.Generic.List[string]]::new()
        foreach ($uncPath in $report.uncCandidates) {
            $reconnectCommands.Add("cmd /c `"net use ${driveLetter}: /delete /y`"")
            $reconnectCommands.Add("cmd /c `"net use ${driveLetter}: $uncPath /persistent:yes`"")
            $reconnectCommands.Add("New-PSDrive -Name $driveLetter -PSProvider FileSystem -Root '$uncPath' -Persist")
        }
        $report.reconnectCommands = @($reconnectCommands | Select-Object -Unique)
    }

    return [pscustomobject]$report
}

function Show-DriveMappingReport {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Report
    )

    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "ドライブマッピング診断: $($Report.drivePath)" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""

    if (-not $Report.configFound) {
        Write-Host "config.json が見つからないため、既定値で診断しています。" -ForegroundColor Yellow
        Write-Host ""
    }

    Write-Host "[1] 直接アクセス" -ForegroundColor Yellow
    if ($Report.directAccess) {
        Write-Host "    OK: $($Report.drivePath) はアクセス可能 ($($Report.directoryCount) ディレクトリ)" -ForegroundColor Green
    }
    else {
        Write-Host "    FAIL: $($Report.drivePath) はアクセス不可" -ForegroundColor Red
    }

    Write-Host "`n[2] レジストリ" -ForegroundColor Yellow
    if ($Report.registryRemotePath) {
        Write-Host "    OK: $($Report.registryRemotePath)" -ForegroundColor Green
    }
    else {
        Write-Host "    FAIL: HKCU:\\Network\\$($Report.driveLetter) から取得できません" -ForegroundColor Red
    }

    Write-Host "`n[3] SMB マッピング" -ForegroundColor Yellow
    if ($Report.smbRemotePath) {
        Write-Host "    OK: $($Report.smbRemotePath) [$($Report.smbStatus)]" -ForegroundColor Green
    }
    else {
        Write-Host "    FAIL: SMB マッピングなし" -ForegroundColor Red
    }

    Write-Host "`n[4] PSDrive" -ForegroundColor Yellow
    if ($Report.psDriveRoot -or $Report.psDriveDisplayRoot) {
        Write-Host "    OK: Root=$($Report.psDriveRoot) DisplayRoot=$($Report.psDriveDisplayRoot)" -ForegroundColor Green
    }
    else {
        Write-Host "    FAIL: PSDrive なし" -ForegroundColor Red
    }

    Write-Host "`n[5] net use" -ForegroundColor Yellow
    if ($Report.netUseLine) {
        Write-Host "    OK: $($Report.netUseLine.Trim())" -ForegroundColor Green
        if ($Report.netUseIssue) {
            Write-Host "    Issue: $($Report.netUseIssue)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "    FAIL: net use にエントリなし" -ForegroundColor Red
    }

    Write-Host "`n[6] config の UNC" -ForegroundColor Yellow
    if ($Report.projectsDirUnc) {
        Write-Host "    設定値: $($Report.projectsDirUnc)" -ForegroundColor White
        if ($Report.uncAccessible) {
            Write-Host "    OK: UNC パスに直接アクセス可能" -ForegroundColor Green
        }
        else {
            Write-Host "    WARN: UNC パスに直接アクセスできません" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "    FAIL: projectsDirUnc 未設定" -ForegroundColor Red
    }

    Write-Host "`n[7] 名前解決/疎通" -ForegroundColor Yellow
    if ($Report.targetHost) {
        Write-Host "    Host: $($Report.targetHost)" -ForegroundColor White
        Write-Host "    DNS: $(if ($null -eq $Report.dnsResolved) { 'N/A' } elseif ($Report.dnsResolved) { 'OK' } else { 'FAIL' })" -ForegroundColor $(if ($Report.dnsResolved -eq $false) { 'Yellow' } else { 'White' })
        Write-Host "    Ping: $(if ($null -eq $Report.pingReachable) { 'N/A' } elseif ($Report.pingReachable) { 'OK' } else { 'FAIL' })" -ForegroundColor $(if ($Report.pingReachable -eq $false) { 'Yellow' } else { 'White' })
        Write-Host "    SMB445: $(if ($null -eq $Report.smbPort445Reachable) { 'N/A' } elseif ($Report.smbPort445Reachable) { 'OK' } else { 'FAIL' })" -ForegroundColor $(if ($Report.smbPort445Reachable -eq $false) { 'Yellow' } else { 'White' })
    }
    else {
        Write-Host "    FAIL: 解析対象ホストなし" -ForegroundColor Red
    }

    Write-Host "`n[Summary]" -ForegroundColor Cyan
    foreach ($path in $Report.uncCandidates) {
        Write-Host "    UNC: $path" -ForegroundColor White
    }
    foreach ($share in $Report.smbShareCandidates) {
        Write-Host "    Share: $share" -ForegroundColor White
    }
    if ($Report.uncCandidates.Count -eq 0) {
        Write-Host "    UNC 候補なし" -ForegroundColor Red
    }
    Write-Host "    Recommendation: $($Report.recommendation)" -ForegroundColor Cyan
    if ($Report.remapCommand) {
        Write-Host "    RemapCommand: $($Report.remapCommand)" -ForegroundColor White
    }
    foreach ($command in @($Report.reconnectCommands)) {
        Write-Host "    Reconnect: $command" -ForegroundColor White
    }
    foreach ($item in $Report.repairAdvice) {
        Write-Host "    Advice: $item" -ForegroundColor White
    }
    Write-Host ""
}

if ($MyInvocation.InvocationName -ne '.') {
    $configPath = Get-StartupConfigPath -StartupRoot $RootDir
    $configInfo = Get-DriveMappingConfig -ConfigPath $configPath
    $report = Get-DriveMappingReport -ConfigInfo $configInfo

    if ($OutputFormat -eq 'Json') {
        $report | ConvertTo-Json -Depth 6
    }
    else {
        Show-DriveMappingReport -Report $report
    }
}
