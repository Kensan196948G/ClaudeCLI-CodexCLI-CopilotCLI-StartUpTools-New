# ============================================================
# ErrorHandler.Tests.ps1 - ErrorHandler.psm1 のユニットテスト
# Pester 5.x
# ============================================================

BeforeAll {
    Import-Module "$PSScriptRoot\..\scripts\lib\ErrorHandler.psm1" -Force
}

Describe 'ErrorHandler モジュール読み込み' {

    It 'モジュールが正常に読み込めること' {
        $module = Get-Module -Name 'ErrorHandler'
        $module | Should -Not -BeNullOrEmpty
    }

    It 'Show-CategorizedError がエクスポートされていること' {
        $cmd = Get-Command -Name 'Show-CategorizedError' -Module 'ErrorHandler' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }

    It 'Get-ErrorCategory がエクスポートされていること' {
        $cmd = Get-Command -Name 'Get-ErrorCategory' -Module 'ErrorHandler' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }

    It 'Show-Error がエクスポートされていること' {
        $cmd = Get-Command -Name 'Show-Error' -Module 'ErrorHandler' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-ErrorCategory' {

    Context 'SSH 関連のエラーメッセージ' {

        It 'SSH キーワードから SSH_CONNECTION カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'SSH接続がタイムアウトしました'
            $result.ToString() | Should -Be 'SSH_CONNECTION'
        }

        It 'authentication キーワードから SSH_CONNECTION カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'authentication failed'
            $result.ToString() | Should -Be 'SSH_CONNECTION'
        }
    }

    Context 'AIツール未インストールのエラーメッセージ' {

        It 'claude not found キーワードから TOOL_NOT_FOUND カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'claude not found'
            $result.ToString() | Should -Be 'TOOL_NOT_FOUND'
        }

        It 'codex not found キーワードから TOOL_NOT_FOUND カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'codex not found'
            $result.ToString() | Should -Be 'TOOL_NOT_FOUND'
        }
    }

    Context 'APIキー未設定のエラーメッセージ' {

        It 'api_key キーワードから API_KEY_MISSING カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'OPENAI_API_KEY not set'
            $result.ToString() | Should -Be 'API_KEY_MISSING'
        }

        It 'apikey キーワードから API_KEY_MISSING カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'api key missing'
            $result.ToString() | Should -Be 'API_KEY_MISSING'
        }
    }

    Context '依存関係不足のエラーメッセージ' {

        It 'node キーワードから DEPENDENCY_MISSING カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'node command not found'
            $result.ToString() | Should -Be 'DEPENDENCY_MISSING'
        }

        It 'curl not installed から DEPENDENCY_MISSING カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'curl not installed'
            $result.ToString() | Should -Be 'DEPENDENCY_MISSING'
        }
    }

    Context 'タイムアウトのエラーメッセージ' {

        It 'timeout キーワードから NETWORK_TIMEOUT カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'connection timed out'
            $result.ToString() | Should -Be 'NETWORK_TIMEOUT'
        }
    }

    Context '不明なエラーメッセージ' {

        It '不明なキーワードで UNKNOWN カテゴリ（デフォルト）を返すこと' {
            $result = Get-ErrorCategory -ErrorMessage '原因不明のエラーです'
            $result.ToString() | Should -Be 'UNKNOWN'
        }
    }

    Context 'ファイルシステムエラー' {

        It 'file/directory キーワードから FILE_SYSTEM カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'ファイルの書き込みに失敗 file write error'
            $result.ToString() | Should -Be 'FILE_SYSTEM'
        }
    }

    Context 'プロセス管理エラー' {

        It 'process/kill キーワードから PROCESS_MANAGEMENT カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'process failed to start'
            $result.ToString() | Should -Be 'PROCESS_MANAGEMENT'
        }
    }

    Context 'ログ操作エラー' {

        It 'log/transcript キーワードから LOG_OPERATION カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'Start-Transcript log operation failed'
            $result.ToString() | Should -Be 'LOG_OPERATION'
        }
    }

    Context 'config mismatch エラー' {

        It 'mismatch/inconsistent キーワードから CONFIG_MISMATCH カテゴリを返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'config mismatch detected'
            $result.ToString() | Should -Be 'CONFIG_MISMATCH'
        }
    }

    Context '偽陽性防止 (ワードバウンダリ)' {

        It '"login failed" は LOG_OPERATION ではなく UNKNOWN を返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'login failed: invalid credentials'
            $result.ToString() | Should -Not -Be 'LOG_OPERATION'
        }

        It '"dialog box appeared" は LOG_OPERATION ではなく UNKNOWN を返すこと' {
            $result = Get-ErrorCategory -ErrorMessage 'unexpected dialog box appeared'
            $result.ToString() | Should -Not -Be 'LOG_OPERATION'
        }

        It '"profile not found" は FILE_SYSTEM ではないこと' {
            $result = Get-ErrorCategory -ErrorMessage 'user profile not found'
            $result.ToString() | Should -Not -Be 'FILE_SYSTEM'
        }

        It '"catalog parse error" は LOG_OPERATION ではないこと' {
            $result = Get-ErrorCategory -ErrorMessage 'catalog parse error occurred'
            $result.ToString() | Should -Not -Be 'LOG_OPERATION'
        }
    }
}

Describe 'Show-CategorizedError' {

    Context 'ThrowAfter = $true の場合（デフォルト）' {

        It '例外をスローすること' {
            { Show-CategorizedError -Category 'SSH_CONNECTION' -Message 'テストエラー' -ThrowAfter $true } |
                Should -Throw
        }

        It 'エラーメッセージが例外に含まれること' {
            { Show-CategorizedError -Category 'CONFIG_INVALID' -Message 'テスト設定エラー' -ThrowAfter $true } |
                Should -Throw -ExpectedMessage '*テスト設定エラー*'
        }
    }

    Context 'ThrowAfter = $false の場合' {

        It '例外をスローしないこと' {
            { Show-CategorizedError -Category 'DEPENDENCY_MISSING' -Message '依存関係テスト' -ThrowAfter $false } |
                Should -Not -Throw
        }
    }
}

Describe 'Show-Error' {

    Context 'ThrowAfter = $true の場合（デフォルト）' {

        It 'メッセージから自動カテゴリ判定して例外をスローすること' {
            { Show-Error -Message 'SSH接続に失敗しました' -ThrowAfter $true } | Should -Throw
        }
    }

    Context 'ThrowAfter = $false の場合' {

        It '自動カテゴリ判定しても例外をスローしないこと' {
            { Show-Error -Message 'テストエラー通知' -ThrowAfter $false } | Should -Not -Throw
        }
    }
}
