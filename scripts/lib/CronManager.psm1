# ============================================================
# CronManager.psm1 - Linux crontab 解析・編集ヘルパ
# ClaudeOS v3.1.0 / メニュー 12 (Cron 登録・編集・削除) の中核
#
# 設計:
#  - CLAUDEOS: <uuid> コメント行で自分が書いたエントリを識別する
#  - crontab -l → パース → 編集 → crontab - で流し込む round-trip
#  - 他のユーザー cron を破壊しないよう「CLAUDEOS: 行 + その直後の cron 式」のみ操作
# ============================================================

Set-StrictMode -Version Latest

$script:EntryPrefix = 'CLAUDEOS'
$script:LauncherPath = '/home/kensan/.claudeos/cron-launcher.sh'
$script:LogsDir = '/home/kensan/.claudeos/logs'

function Set-CronManagerConfig {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal autonomous CLI function; ShouldProcess disrupts unattended operation')]
    param(
        [string]$EntryPrefix = '',
        [string]$LauncherPath = '',
        [string]$LogsDir = ''
    )
    if (-not [string]::IsNullOrWhiteSpace($EntryPrefix)) { $script:EntryPrefix = $EntryPrefix }
    if (-not [string]::IsNullOrWhiteSpace($LauncherPath)) { $script:LauncherPath = $LauncherPath }
    if (-not [string]::IsNullOrWhiteSpace($LogsDir)) { $script:LogsDir = $LogsDir }
}

function Invoke-RemoteCrontab {
    <#
    .SYNOPSIS Linux 側で crontab コマンドを実行する
    .DESCRIPTION
      Action='read'  → crontab -l の出力を文字列で返す (stderr は握りつぶす)
      Action='write' → StdinContent を crontab - に流し込む
    #>
    param(
        [Parameter(Mandatory)][string]$LinuxHost,
        [Parameter(Mandatory)][ValidateSet('read', 'write')][string]$Action,
        [string]$StdinContent = ''
    )

    $sshExe = if ($env:AI_STARTUP_SSH_EXE) { $env:AI_STARTUP_SSH_EXE } else { 'ssh' }

    if ($Action -eq 'read') {
        # crontab -l が空の場合 exit 1 なので、両方ハンドル
        $result = & $sshExe -T -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new `
            -o ControlMaster=no $LinuxHost "crontab -l 2>/dev/null || true"
        if ($null -eq $result) { return '' }
        return ($result -join "`n")
    }

    # write: StdinContent を "crontab -" に流し込む
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $sshExe
    $psi.Arguments = "-T -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o ControlMaster=no $LinuxHost `"crontab -`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $proc.StandardInput.NewLine = "`n"
    $proc.StandardInput.Write($StdinContent.Replace("`r`n", "`n"))
    if (-not $StdinContent.EndsWith("`n")) { $proc.StandardInput.WriteLine() }
    $proc.StandardInput.Close()
    $proc.WaitForExit()
    return $proc.ExitCode
}

function Get-ClaudeOSCronEntry {
    <#
    .SYNOPSIS 現在の crontab から CLAUDEOS: 行と対応する cron 式を抽出
    #>
    param([Parameter(Mandatory)][string]$LinuxHost)

    $raw = Invoke-RemoteCrontab -LinuxHost $LinuxHost -Action 'read'
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    $lines = $raw -split "`n"
    $entries = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match "^\s*#\s*$($script:EntryPrefix):([\w-]+)\s*(.*)$") {
            $id = $matches[1]
            $metaRaw = $matches[2]
            $meta = @{}
            foreach ($kv in ($metaRaw -split '\s+')) {
                if ($kv -match '^(\w+)=(.+)$') {
                    $meta[$matches[1]] = $matches[2]
                }
            }
            $cronLine = if (($i + 1) -lt $lines.Count) { $lines[$i + 1] } else { '' }
            $entries += [pscustomobject]@{
                Id        = $id
                Project   = if ($meta.ContainsKey('project')) { $meta['project'] } else { '' }
                Duration  = if ($meta.ContainsKey('duration')) { [int]$meta['duration'] } else { 300 }
                Created   = if ($meta.ContainsKey('created')) { $meta['created'] } else { '' }
                CronExpr  = ($cronLine -split '\s+', 6)[0..4] -join ' '
                CommentLine = $line
                CronLine    = $cronLine
            }
        }
    }
    return $entries
}

function Format-CronExpression {
    <#
    .SYNOPSIS 曜日（0=日〜6=土、複数可）と HH:MM から cron 式を生成
    #>
    param(
        [Parameter(Mandatory)][int[]]$DayOfWeek,
        [Parameter(Mandatory)][string]$Time
    )

    if ($Time -notmatch '^(\d{1,2}):(\d{2})$') {
        throw "時刻は HH:MM 形式で指定してください (例: 21:00)"
    }
    $hour = [int]$matches[1]
    $minute = [int]$matches[2]
    if ($hour -lt 0 -or $hour -gt 23) { throw "時間は 0-23 の範囲で指定してください" }
    if ($minute -lt 0 -or $minute -gt 59) { throw "分は 0-59 の範囲で指定してください" }

    $dowStr = ($DayOfWeek | Sort-Object -Unique | ForEach-Object { $_.ToString() }) -join ','
    foreach ($d in $DayOfWeek) {
        if ($d -lt 0 -or $d -gt 6) { throw "曜日は 0(日)〜6(土) の範囲で指定してください" }
    }
    return "$minute $hour * * $dowStr"
}

function New-CronEntryId {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Factory function returns in-memory object; no persistent system state is modified')]
    param()
    return [Guid]::NewGuid().ToString('N').Substring(0, 8)
}

function Add-ClaudeOSCronEntry {
    <#
    .SYNOPSIS 新規 CLAUDEOS エントリを crontab 末尾に追加
    #>
    param(
        [Parameter(Mandatory)][string]$LinuxHost,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][int[]]$DayOfWeek,
        [Parameter(Mandatory)][string]$Time,
        [int]$DurationMinutes = 300
    )

    $cronExpr = Format-CronExpression -DayOfWeek $DayOfWeek -Time $Time
    $id = New-CronEntryId
    $created = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    $logFilePattern = "$($script:LogsDir)/cron-`$(date +\%Y\%m\%d-\%H\%M\%S).log"
    $command = "$($script:LauncherPath) $Project $DurationMinutes >> $logFilePattern 2>&1"

    $commentLine = "# $($script:EntryPrefix):$id project=$Project duration=$DurationMinutes created=$created"
    $cronLine = "$cronExpr $command"

    $current = Invoke-RemoteCrontab -LinuxHost $LinuxHost -Action 'read'
    if ($null -eq $current) { $current = '' }
    $newContent = $current.TrimEnd("`n")
    if (-not [string]::IsNullOrWhiteSpace($newContent)) { $newContent += "`n" }
    $newContent += "$commentLine`n$cronLine`n"

    $exitCode = Invoke-RemoteCrontab -LinuxHost $LinuxHost -Action 'write' -StdinContent $newContent
    if ($exitCode -ne 0) {
        throw "crontab 更新に失敗 (exit=$exitCode)"
    }

    return [pscustomobject]@{
        Id = $id
        Project = $Project
        CronExpr = $cronExpr
        Duration = $DurationMinutes
        Created = $created
    }
}

function Remove-ClaudeOSCronEntry {
    <#
    .SYNOPSIS ID 指定で CLAUDEOS エントリを削除（コメント行 + 直後の cron 式の 2 行セット）
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal autonomous CLI function; ShouldProcess disrupts unattended operation')]
    param(
        [Parameter(Mandatory)][string]$LinuxHost,
        [Parameter(Mandatory)][string]$Id
    )

    $raw = Invoke-RemoteCrontab -LinuxHost $LinuxHost -Action 'read'
    if ([string]::IsNullOrWhiteSpace($raw)) { return 0 }

    $lines = $raw -split "`n"
    $result = @()
    $removed = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match "^\s*#\s*$($script:EntryPrefix):$([regex]::Escape($Id))\b") {
            # skip comment line + next cron line
            $i++  # 次の行もスキップ
            $removed++
            continue
        }
        $result += $line
    }

    $newContent = ($result -join "`n")
    if (-not $newContent.EndsWith("`n")) { $newContent += "`n" }

    $exitCode = Invoke-RemoteCrontab -LinuxHost $LinuxHost -Action 'write' -StdinContent $newContent
    if ($exitCode -ne 0) {
        throw "crontab 更新に失敗 (exit=$exitCode)"
    }
    return $removed
}

function Remove-AllClaudeOSCronEntry {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal autonomous CLI function; ShouldProcess disrupts unattended operation')]
    param([Parameter(Mandatory)][string]$LinuxHost)

    $entries = Get-ClaudeOSCronEntry -LinuxHost $LinuxHost
    $count = 0
    foreach ($e in $entries) {
        $count += Remove-ClaudeOSCronEntry -LinuxHost $LinuxHost -Id $e.Id
    }
    return $count
}

function Get-DayOfWeekLabel {
    param([int]$Dow)
    $labels = @('日', '月', '火', '水', '木', '金', '土')
    if ($Dow -ge 0 -and $Dow -le 6) { return $labels[$Dow] }
    return "?"
}

function Format-CronEntryForDisplay {
    param([pscustomobject]$Entry)

    $parts = $Entry.CronExpr -split '\s+'
    $minute = $parts[0]; $hour = $parts[1]; $dow = $parts[4]
    $dowLabel = ($dow -split ',' | ForEach-Object { Get-DayOfWeekLabel -Dow ([int]$_) }) -join '/'
    return "[{0}] project={1}  {2} {3}:{4}  duration={5}m  (created {6})" -f `
        $Entry.Id, $Entry.Project, $dowLabel, $hour, ("{0:00}" -f [int]$minute), $Entry.Duration, $Entry.Created
}

Export-ModuleMember -Function `
    Set-CronManagerConfig, `
    Get-ClaudeOSCronEntry, `
    Add-ClaudeOSCronEntry, `
    Remove-ClaudeOSCronEntry, `
    Remove-AllClaudeOSCronEntry, `
    Format-CronExpression, `
    Format-CronEntryForDisplay, `
    New-CronEntryId, `
    Get-DayOfWeekLabel
