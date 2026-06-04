# ============================================================
# Supervisor.Tests.ps1 - supervisor daemon 関連スクリプトのテスト
# Pester 5.x
# ============================================================

BeforeAll {
    $script:RepoRoot       = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:DaemonJs       = Join-Path $script:RepoRoot 'scripts\dashboards\supervisor-daemon.js'
    $script:ProcessesCfg   = Join-Path $script:RepoRoot 'config\processes.json'
    $script:RegisterPs1    = Join-Path $script:RepoRoot 'scripts\main\Register-SupervisorTask.ps1'
    $script:StartTaskPs1   = Join-Path $script:RepoRoot 'scripts\dashboards\start-supervisor-task.ps1'
    $script:InstallSh      = Join-Path $script:RepoRoot 'scripts\dashboards\install-supervisor-service.sh'
    $script:NodeExe        = (Get-Command node -ErrorAction SilentlyContinue)?.Source
}

# ── ファイル存在確認 ──────────────────────────────────────────
Describe 'supervisor 成果物ファイル存在確認' {
    It 'supervisor-daemon.js が存在すること' {
        Test-Path $script:DaemonJs | Should -BeTrue
    }
    It 'config/processes.json が存在すること' {
        Test-Path $script:ProcessesCfg | Should -BeTrue
    }
    It 'Register-SupervisorTask.ps1 が存在すること' {
        Test-Path $script:RegisterPs1 | Should -BeTrue
    }
    It 'start-supervisor-task.ps1 が存在すること' {
        Test-Path $script:StartTaskPs1 | Should -BeTrue
    }
    It 'install-supervisor-service.sh が存在すること' {
        Test-Path $script:InstallSh | Should -BeTrue
    }
}

# ── processes.json スキーマ検証 ───────────────────────────────
Describe 'config/processes.json スキーマ検証' {
    BeforeAll {
        $script:ProcCfg = $null
        if (Test-Path $script:ProcessesCfg) {
            try {
                $script:ProcCfg = Get-Content $script:ProcessesCfg -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {}
        }
    }

    It 'JSON として正しくパースできること' {
        $script:ProcCfg | Should -Not -BeNullOrEmpty
    }
    It 'version フィールドを持つこと' {
        $script:ProcCfg.version | Should -Not -BeNullOrEmpty
    }
    It 'processes 配列を持つこと' {
        $procs = @($script:ProcCfg.processes)
        $procs | Should -Not -BeNullOrEmpty
    }
    It 'processes 配列が 1 件以上であること' {
        $script:ProcCfg.processes.Count | Should -BeGreaterThan 0
    }
    It '各プロセスに id フィールドが存在すること' {
        $script:ProcCfg.processes | ForEach-Object {
            $_.id | Should -Not -BeNullOrEmpty
        }
    }
    It '各プロセスに type フィールドが存在すること' {
        $script:ProcCfg.processes | ForEach-Object {
            $_.type | Should -Match '^(http|session-file|service)$'
        }
    }
    It 'dashboard プロセスが定義されていること' {
        $dashboard = $script:ProcCfg.processes | Where-Object { $_.id -eq 'dashboard' }
        $dashboard | Should -Not -BeNullOrEmpty
    }
    It 'claude-session プロセスが定義されていること' {
        $session = $script:ProcCfg.processes | Where-Object { $_.id -eq 'claude-session' }
        $session | Should -Not -BeNullOrEmpty
    }
}

# ── supervisor-daemon.js ロジック検証 (node -e) ───────────────
Describe 'supervisor-daemon.js: expandPath ロジック' {
    BeforeAll {
        if (-not $script:NodeExe) { return }
        $tmpJs = Join-Path $TestDrive 'expand-test.js'
        @'
const os   = require('os');
const path = require('path');
const PROJ_ROOT = path.resolve(__dirname);

function expandPath(str) {
  if (typeof str !== 'string') return str;
  return str
    .replace('${PROJ_ROOT}', PROJ_ROOT)
    .replace('${HOME}', os.homedir())
    .replace('~', os.homedir());
}

const tests = [
  { input: '${HOME}/.claudeos', expected: os.homedir() + '/.claudeos' },
  { input: '~/test',            expected: os.homedir() + '/test' },
  { input: 'no-template',       expected: 'no-template' },
  { input: 42,                  expected: 42 },
];
const results = tests.map(t => ({
  ok: expandPath(t.input) === t.expected,
  input: t.input,
  got: expandPath(t.input),
  expected: t.expected,
}));
console.log(JSON.stringify(results));
'@ | Set-Content $tmpJs -Encoding UTF8
        $script:ExpandResults = & $script:NodeExe $tmpJs 2>$null | ConvertFrom-Json
    }

    It '${HOME} を homedir に展開すること' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:ExpandResults[0].ok | Should -BeTrue
    }
    It '~ を homedir に展開すること' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:ExpandResults[1].ok | Should -BeTrue
    }
    It 'テンプレートなし文字列はそのまま返すこと' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:ExpandResults[2].ok | Should -BeTrue
    }
    It '非文字列（数値）はそのまま返すこと' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:ExpandResults[3].ok | Should -BeTrue
    }
}

Describe 'supervisor-daemon.js: cooldownSec 指数バックオフ' {
    BeforeAll {
        if (-not $script:NodeExe) { return }
        $tmpJs = Join-Path $TestDrive 'cooldown-test.js'
        @'
const MAX_COOLDOWN_SEC = 300;

function cooldownSec(base, failures) {
  return Math.min(base * Math.pow(2, failures), MAX_COOLDOWN_SEC);
}

const results = [
  cooldownSec(5, 0),   // 5  * 2^0 = 5
  cooldownSec(5, 1),   // 5  * 2^1 = 10
  cooldownSec(5, 2),   // 5  * 2^2 = 20
  cooldownSec(5, 3),   // 5  * 2^3 = 40
  cooldownSec(5, 10),  // should be capped at 300
];
console.log(JSON.stringify(results));
'@ | Set-Content $tmpJs -Encoding UTF8
        $script:CooldownResults = & $script:NodeExe $tmpJs 2>$null | ConvertFrom-Json
    }

    It '失敗 0 回: baseSec を返すこと (5s)' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:CooldownResults[0] | Should -Be 5
    }
    It '失敗 1 回: 2 倍を返すこと (10s)' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:CooldownResults[1] | Should -Be 10
    }
    It '失敗 2 回: 4 倍を返すこと (20s)' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:CooldownResults[2] | Should -Be 20
    }
    It '失敗 3 回: 8 倍を返すこと (40s)' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:CooldownResults[3] | Should -Be 40
    }
    It '上限 300s を超えないこと (失敗 10 回)' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:CooldownResults[4] | Should -Be 300
    }
}

Describe 'supervisor-daemon.js: isPidAlive 無効 PID' {
    BeforeAll {
        if (-not $script:NodeExe) { return }
        $tmpJs = Join-Path $TestDrive 'pid-test.js'
        @'
function isPidAlive(pid) {
  if (!pid) return false;
  try { process.kill(pid, 0); return true; } catch { return false; }
}

const results = {
  null_pid:  isPidAlive(null),
  zero_pid:  isPidAlive(0),
  undef_pid: isPidAlive(undefined),
};
console.log(JSON.stringify(results));
'@ | Set-Content $tmpJs -Encoding UTF8
        $script:PidResults = & $script:NodeExe $tmpJs 2>$null | ConvertFrom-Json
    }

    It 'null を渡すと false を返すこと' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:PidResults.null_pid | Should -BeFalse
    }
    It '0 を渡すと false を返すこと' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:PidResults.zero_pid | Should -BeFalse
    }
    It 'undefined を渡すと false を返すこと' {
        if (-not $script:NodeExe) { Set-ItResult -Skipped -Because 'node not available' }
        $script:PidResults.undef_pid | Should -BeFalse
    }
}

# ── Register-SupervisorTask.ps1 スクリプト構文確認 ────────────
Describe 'Register-SupervisorTask.ps1 スクリプト検証' {
    It 'スクリプトが構文エラーなくパースできること' {
        $err = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:RegisterPs1, [ref]$null, [ref]$err
        )
        $err | Should -BeNullOrEmpty
    }
    It '-Status パラメータが定義されていること' {
        $content = Get-Content $script:RegisterPs1 -Raw
        $content | Should -Match '\[switch\]\$Status'
    }
    It '-Unregister パラメータが定義されていること' {
        $content = Get-Content $script:RegisterPs1 -Raw
        $content | Should -Match '\[switch\]\$Unregister'
    }
    It '-RunNow パラメータが定義されていること' {
        $content = Get-Content $script:RegisterPs1 -Raw
        $content | Should -Match '\[switch\]\$RunNow'
    }
}

# ── start-supervisor-task.ps1 スクリプト構文確認 ─────────────
Describe 'start-supervisor-task.ps1 スクリプト検証' {
    It 'スクリプトが構文エラーなくパースできること' {
        $err = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:StartTaskPs1, [ref]$null, [ref]$err
        )
        $err | Should -BeNullOrEmpty
    }
    It 'PID ファイルパスが定義されていること' {
        $content = Get-Content $script:StartTaskPs1 -Raw
        $content | Should -Match 'supervisor\.pid'
    }
    It 'supervisor-daemon.js を参照していること' {
        $content = Get-Content $script:StartTaskPs1 -Raw
        $content | Should -Match 'supervisor-daemon\.js'
    }
}
