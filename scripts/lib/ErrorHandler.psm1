Set-StrictMode -Version Latest

# ============================================================
# ErrorHandler.psm1 - カテゴリ別エラーハンドリングモジュール
# ClaudeCLI-CodexCLI-CopilotCLI-StartUpTools v2.0.0
# ============================================================

# エラーカテゴリの定義
enum ErrorCategory {
    SSH_CONNECTION          # SSH 接続エラー
    CONFIG_INVALID          # 設定ファイルエラー
    DEPENDENCY_MISSING      # 依存関係不足（ツール未インストール）
    TOOL_NOT_FOUND          # AI CLIツールが見つからない
    API_KEY_MISSING         # APIキー未設定
    DRIVE_ACCESS            # ドライブアクセスエラー
    PERMISSION_DENIED       # 権限エラー
    NETWORK_TIMEOUT         # ネットワークタイムアウト
    FILE_SYSTEM             # ファイル/ディレクトリ操作エラー
    PROCESS_MANAGEMENT      # プロセス起動/終了エラー
    CONFIG_MISMATCH         # config.json と実態の不整合
    LOG_OPERATION           # ログ書き込み/ローテーションエラー
    UNKNOWN                 # 未分類エラー
}

# カテゴリごとの絵文字
$script:CategoryEmoji = @{
    SSH_CONNECTION     = "🔐"
    CONFIG_INVALID     = "⚙️"
    DEPENDENCY_MISSING = "📦"
    TOOL_NOT_FOUND     = "🔍"
    API_KEY_MISSING    = "🔑"
    DRIVE_ACCESS       = "💾"
    PERMISSION_DENIED  = "🚫"
    NETWORK_TIMEOUT    = "⏱️"
    FILE_SYSTEM        = "📄"
    PROCESS_MANAGEMENT = "⚡"
    CONFIG_MISMATCH    = "🔀"
    LOG_OPERATION      = "📝"
    UNKNOWN            = "❓"
}

# カテゴリごとの推奨アクション
$script:CategorySolutions = @{
    SSH_CONNECTION = @(
        "1. SSH 鍵の権限を確認: icacls ~/.ssh/id_ed25519",
        "2. ~/.ssh/config の設定を確認",
        "3. ホストへの疎通確認: ping <hostname>",
        "4. 詳細ログ確認: ssh -vvv <hostname>"
    )
    CONFIG_INVALID = @(
        "1. config.json の JSON 構文を確認",
        "2. 必須フィールドが存在するか確認: version, linuxHost, tools",
        "3. config.json.template と比較して不足項目を確認"
    )
    DEPENDENCY_MISSING = @(
        "1. 不足しているコマンドをインストール",
        "2. Node.js: https://nodejs.org/ からインストール",
        "3. 診断スクリプトを実行: .\scripts\test\Test-AllTools.ps1"
    )
    TOOL_NOT_FOUND = @(
        "1. claude インストール: npm install -g @anthropic-ai/claude-code",
        "2. codex インストール: npm install -g @openai/codex",
        "3. copilot インストール: gh extension install github/gh-copilot",
        "4. 診断スクリプトを実行: .\scripts\test\Test-AllTools.ps1"
    )
    API_KEY_MISSING = @(
        "1. ANTHROPIC_API_KEY: https://console.anthropic.com/ で取得",
        "2. OPENAI_API_KEY: https://platform.openai.com/api-keys で取得",
        "3. GitHub Copilot: gh auth login で認証",
        "4. 環境変数に設定: `$env:ANTHROPIC_API_KEY = 'your-key'" # arch-check:ignore
    )
    DRIVE_ACCESS = @(
        "1. ドライブ診断を実行: start.bat → オプション 6",
        "2. config.json に projectsDirUnc を設定",
        "3. UNC パスへの直接アクセスを確認: Test-Path '\\\\server\\share'"
    )
    PERMISSION_DENIED = @(
        "1. 管理者権限で PowerShell を起動",
        "2. ファイル/ディレクトリの権限を確認",
        "3. Windows Defender や アンチウイルスの除外設定を確認"
    )
    NETWORK_TIMEOUT = @(
        "1. ネットワーク接続を確認: ping <hostname>",
        "2. ファイアウォール設定を確認（ポート 22）",
        "3. タイムアウト値を増やす: ConnectTimeout=10"
    )
    FILE_SYSTEM = @(
        "1. ファイル/ディレクトリの存在を確認",
        "2. ディスク容量を確認: Get-PSDrive",
        "3. ファイルがロックされていないか確認"
    )
    PROCESS_MANAGEMENT = @(
        "1. プロセスの状態を確認: Get-Process",
        "2. 管理者権限で実行してください",
        "3. タスクマネージャーで手動終了を試行"
    )
    CONFIG_MISMATCH = @(
        "1. config.json の設定値と実際の環境を比較",
        "2. config.json を最新テンプレートと照合",
        "3. 設定を再生成: config.json.template を参照"
    )
    LOG_OPERATION = @(
        "1. ログディレクトリの書き込み権限を確認",
        "2. ディスク容量を確認",
        "3. logging.enabled = false で一時的にログを無効化"
    )
    UNKNOWN = @(
        "1. エラーメッセージの詳細を確認",
        "2. ログファイルを確認",
        "3. 問題が再現するか確認してください"
    )
}

<#
.SYNOPSIS
    カテゴリ別のエラーメッセージを表示

.DESCRIPTION
    エラーをカテゴリごとに分類し、適切な絵文字・色・推奨アクションと共に表示

.PARAMETER Category
    エラーカテゴリ（ErrorCategory enum）

.PARAMETER Message
    エラーメッセージ

.PARAMETER Details
    エラーの詳細情報（オプション）

.PARAMETER ThrowAfter
    表示後に例外をスローするか（デフォルト: $true）

.EXAMPLE
    Show-CategorizedError -Category SSH_CONNECTION -Message "SSH接続がタイムアウトしました"

.EXAMPLE
    Show-CategorizedError -Category TOOL_NOT_FOUND -Message "claude コマンドが見つかりません" -Details @{Tool="claude"; InstallCmd="npm install -g @anthropic-ai/claude-code"}
#>
function Show-CategorizedError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ErrorCategory]$Category,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [hashtable]$Details = @{},

        [Parameter(Mandatory=$false)]
        [bool]$ThrowAfter = $true
    )

    $emoji = $script:CategoryEmoji[$Category]
    $solutions = $script:CategorySolutions[$Category]

    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Red
    Write-Host "$emoji エラーカテゴリ: $Category" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Red

    Write-Host "❌ $Message`n" -ForegroundColor Red

    # 詳細情報（オプション）
    if ($Details.Count -gt 0) {
        Write-Host "📋 詳細情報:" -ForegroundColor Yellow
        foreach ($key in $Details.Keys) {
            Write-Host "   $key : $($Details[$key])" -ForegroundColor White
        }
        Write-Host ""
    }

    # 推奨アクション
    Write-Host "💡 推奨アクション:" -ForegroundColor Cyan
    foreach ($solution in $solutions) {
        Write-Host "   $solution" -ForegroundColor White
    }
    Write-Host ""

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Red

    if ($ThrowAfter) {
        throw $Message
    }
}

<#
.SYNOPSIS
    エラーメッセージから自動的にカテゴリを推定

.DESCRIPTION
    エラーメッセージのキーワードからカテゴリを自動判定

.PARAMETER ErrorMessage
    エラーメッセージ

.EXAMPLE
    $category = Get-ErrorCategory -ErrorMessage "SSH接続がタイムアウトしました"
    # → ErrorCategory::SSH_CONNECTION
#>
function Get-ErrorCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage
    )

    $message = $ErrorMessage.ToLower()

    # キーワードベースの分類
    if ($message -match "ssh|authorized|authentication|connection refused") {
        return [ErrorCategory]::SSH_CONNECTION
    }
    elseif ($message -match "config\.json|invalid json|parse error|schema") {
        return [ErrorCategory]::CONFIG_INVALID
    }
    elseif ($message -match "api.?key|apikey|api_key") {
        return [ErrorCategory]::API_KEY_MISSING
    }
    elseif ($message -match "command not found|not installed|not recognized|jq|curl|npx|node") {
        return [ErrorCategory]::DEPENDENCY_MISSING
    }
    elseif ($message -match "claude.*not found|codex.*not found|copilot.*not found|tool.*not found|which.*claude|which.*codex") {
        return [ErrorCategory]::TOOL_NOT_FOUND
    }
    elseif ($message -match "drive|unc path|network|x:\\|z:\\") {
        return [ErrorCategory]::DRIVE_ACCESS
    }
    elseif ($message -match "permission|access.*denied|unauthorized|forbidden") {
        return [ErrorCategory]::PERMISSION_DENIED
    }
    elseif ($message -match "timeout|timed out|unreachable") {
        return [ErrorCategory]::NETWORK_TIMEOUT
    }
    elseif ($message -match "\bfile\b|\bdirectory\b|\bfolder\b|write.*fail|read.*fail|\bpath\b.*not") {
        return [ErrorCategory]::FILE_SYSTEM
    }
    elseif ($message -match "\bprocess\b|\bkill\b|stop-process|start-process|\bpid\b") {
        return [ErrorCategory]::PROCESS_MANAGEMENT
    }
    elseif ($message -match "mismatch|inconsistent|out of sync") {
        return [ErrorCategory]::CONFIG_MISMATCH
    }
    elseif ($message -match "\blog\b|\btranscript\b|\brotation\b|archive.*\blog\b") {
        return [ErrorCategory]::LOG_OPERATION
    }
    else {
        return [ErrorCategory]::UNKNOWN
    }
}

<#
.SYNOPSIS
    簡易エラー表示（カテゴリ自動判定）

.DESCRIPTION
    エラーメッセージから自動的にカテゴリを判定して表示

.PARAMETER Message
    エラーメッセージ

.PARAMETER ThrowAfter
    表示後に例外をスローするか

.EXAMPLE
    Show-Error "SSH接続がタイムアウトしました"
    # → 自動的に SSH_CONNECTION カテゴリと判定して表示
#>
function Show-Error {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [hashtable]$Details = @{},

        [Parameter(Mandatory=$false)]
        [bool]$ThrowAfter = $true
    )

    $category = Get-ErrorCategory -ErrorMessage $Message

    Show-CategorizedError -Category $category -Message $Message -Details $Details -ThrowAfter $ThrowAfter
}

# モジュールのエクスポート
Export-ModuleMember -Function @(
    'Show-CategorizedError',
    'Get-ErrorCategory',
    'Show-Error'
)
