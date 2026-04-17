# ============================================================
# SSHHelper.psm1 - SSH接続ヘルパーモジュール
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.0.0
# ============================================================

<#
.SYNOPSIS
    bash変数として安全にエスケープ

.DESCRIPTION
    シングルクォートで囲み、内部のシングルクォートを '\'' でエスケープする。
    SSHコマンドライン引数として安全に使用できる形式に変換する。

.PARAMETER Value
    エスケープする文字列

.EXAMPLE
    ConvertTo-EscapedSSHArgument "hello 'world'"
    # → 'hello '\''world'\'''
#>
function ConvertTo-EscapedSSHArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Value
    )

    # シングルクォートを '\'' でエスケープしてからシングルクォートで囲む
    $escaped = $Value -replace "'", "'\''"
    return "'$escaped'"
}

<#
.SYNOPSIS
    SSH接続事前テスト

.DESCRIPTION
    指定ホストへのSSH接続が可能かどうかを確認する。
    失敗した場合は詳細な診断メッセージを表示する。

.PARAMETER Host
    接続先ホスト名またはIPアドレス

.PARAMETER TimeoutSeconds
    接続タイムアウト秒数（デフォルト: 5）

.EXAMPLE
    Test-SSHConnection -Host "kensan1969"
    Test-SSHConnection -Host "192.168.0.185" -TimeoutSeconds 10
#>
function Test-SSHConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Host,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 5
    )

    try {
        Write-Host "🔐 SSH接続テスト中: $Host ..." -ForegroundColor Cyan

        # SSHでechoコマンドを実行して接続確認
        $result = & ssh -o ConnectTimeout=$TimeoutSeconds `
                        -o BatchMode=yes `
                        -o StrictHostKeyChecking=accept-new `
                        -o ControlMaster=no `
                        -o ControlPath=none `
                        $Host "echo OK" 2>&1

        if ($LASTEXITCODE -eq 0 -and $result -match "OK") {
            Write-Host "✅ SSH接続成功: $Host" -ForegroundColor Green
            return $true
        }
        else {
            Write-Warning "❌ SSH接続失敗: $Host (終了コード: $LASTEXITCODE)"
            Write-Warning "   出力: $result"
            Show-SSHDiagnostics -HostName $Host
            return $false
        }
    }
    catch {
        Write-Warning "❌ SSH接続中に例外が発生しました: $_"
        Show-SSHDiagnostics -HostName $Host
        return $false
    }
}

<#
.SYNOPSIS
    SSH診断メッセージを表示（内部ヘルパー）
#>
function Show-SSHDiagnostics {
    param([string]$HostName)

    Write-Host "`n💡 SSH接続診断:" -ForegroundColor Yellow
    Write-Host "   1. SSH鍵の権限を確認: icacls `"$env:USERPROFILE\.ssh\id_ed25519`"" -ForegroundColor White
    Write-Host "   2. ~/.ssh/config の設定を確認" -ForegroundColor White
    Write-Host "   3. ホストへの疎通確認: ping $HostName" -ForegroundColor White
    Write-Host "   4. 詳細ログ確認: ssh -vvv $HostName" -ForegroundColor White
    Write-Host ""
}

<#
.SYNOPSIS
    base64エンコードしてSSH経由でbashスクリプトを実行

.DESCRIPTION
    bashスクリプトをbase64エンコードしてSSH経由でリモートホストに送信・実行する。
    日本語文字、JSON特殊文字、バッククォート等の破損を防止する。

.PARAMETER Host
    接続先ホスト名またはIPアドレス

.PARAMETER Script
    実行するbashスクリプト（生テキスト）

.EXAMPLE
    Invoke-SSHBatch -Host "kensan1969" -Script "echo 'Hello World'"
#>
function Invoke-SSHBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Host,

        [Parameter(Mandatory=$true)]
        [string]$Script
    )

    try {
        # UTF-8でbase64エンコード（LF改行を保持）
        $scriptLf = $Script -replace "`r`n", "`n" -replace "`r", "`n"
        $encodedBytes = [System.Text.Encoding]::UTF8.GetBytes($scriptLf)
        $base64 = [Convert]::ToBase64String($encodedBytes)

        Write-Host "📡 SSHバッチ実行中: $Host ..." -ForegroundColor Cyan

        # base64デコードしてbashで実行
        $sshCommand = "echo '$base64' | base64 -d | bash"

        & ssh -t `
              -o ConnectTimeout=15 `
              -o ControlMaster=no `
              -o ControlPath=none `
              $Host $sshCommand

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "⚠️ SSHバッチ実行が非ゼロで終了しました (コード: $LASTEXITCODE)"
        }

        return $LASTEXITCODE
    }
    catch {
        Write-Warning "❌ SSHバッチ実行中にエラーが発生しました: $_"
        throw
    }
}

# モジュールのエクスポート
Export-ModuleMember -Function @(
    'ConvertTo-EscapedSSHArgument',
    'Test-SSHConnection',
    'Invoke-SSHBatch'
)
