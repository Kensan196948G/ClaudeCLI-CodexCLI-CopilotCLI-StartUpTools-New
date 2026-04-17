# ============================================================
# StatuslineManager.psm1 - Statusline グローバル設定の Linux 同期
# ClaudeOS v3.1.0 / メニュー 13 の中核
# ============================================================

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Extracts the statusLine section from the Windows-side ~/.claude/settings.json file.
#>
function Get-GlobalStatusLineConfig {
    param([string]$SettingsPath = '')

    if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
        $SettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
    }

    if (-not (Test-Path $SettingsPath)) {
        return [pscustomobject]@{
            found = $false
            path = $SettingsPath
            statusLine = $null
            raw = $null
        }
    }

    try {
        $content = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $statusLine = if ($content.PSObject.Properties.Name -contains 'statusLine') { $content.statusLine } else { $null }
        return [pscustomobject]@{
            found = $true
            path = $SettingsPath
            statusLine = $statusLine
            raw = $content
        }
    }
    catch {
        throw "設定ファイルの解析に失敗しました: $SettingsPath ($($_.Exception.Message))"
    }
}

<#
.SYNOPSIS
    Merges the statusLine configuration into the remote Linux host's ~/.claude/settings.json via SSH.
#>
function Invoke-RemoteSettingsSync {
    param(
        [Parameter(Mandatory)][string]$LinuxHost,
        [Parameter(Mandatory)][object]$StatusLine,
        [switch]$Backup
    )

    $jsonPayload = $StatusLine | ConvertTo-Json -Depth 10 -Compress
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($jsonPayload))
    $backupLine = if ($Backup) {
        'if [ -f "$TARGET" ]; then cp "$TARGET" "$TARGET.bak-$(date +%Y%m%d-%H%M%S)"; fi'
    } else { '' }

    $script = @"
set -e
TARGET="`$HOME/.claude/settings.json"
mkdir -p "`$(dirname "`$TARGET")"
$backupLine
if [ ! -f "`$TARGET" ]; then
  echo "{}" > "`$TARGET"
fi
python3 - "`$TARGET" "$b64" <<'PYEOF'
import json, sys, base64
path = sys.argv[1]
status_line = json.loads(base64.b64decode(sys.argv[2]).decode('utf-8'))
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception:
    data = {}
data['statusLine'] = status_line
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print('[OK] statusLine を適用しました:', path)
PYEOF
"@

    $sshExe = if ($env:AI_STARTUP_SSH_EXE) { $env:AI_STARTUP_SSH_EXE } else { 'ssh' }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $sshExe
    $psi.Arguments = "-T -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o ControlMaster=no $LinuxHost `"bash -s`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $proc.StandardInput.NewLine = "`n"
    $proc.StandardInput.Write(($script -replace "`r`n", "`n"))
    $proc.StandardInput.WriteLine()
    $proc.StandardInput.Close()
    $proc.WaitForExit()
    return $proc.ExitCode
}

Export-ModuleMember -Function Get-GlobalStatusLineConfig, Invoke-RemoteSettingsSync
