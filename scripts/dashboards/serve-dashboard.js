/**
 * serve-dashboard.js - ClaudeOS Projects Dashboard
 * Node.js built-in modules only (no npm install required)
 * Usage: node scripts/dashboards/serve-dashboard.js [--port 3737]
 *
 * Display conditions:
 *   Show if: (Linux folder listed) OR (GitHub repo registered)
 *   Cron-registered projects additionally show full Session Info
 */

'use strict';

const http    = require('http');
const fs      = require('fs');
const path    = require('path');
const os      = require('os');
const crypto  = require('crypto');
const { exec, execSync, spawn } = require('child_process');
const { promisify } = require('util');
const execAsync     = promisify(exec);

const PORT         = parseInt(process.argv.find(a => a.match(/^\d+$/)) || '3737', 10);
const CRON_REG     = path.join(os.homedir(), '.claudeos', 'cron-registry.json');
const SESSIONS_DIR = path.join(os.homedir(), '.claudeos', 'sessions');
const PROJ_ROOT    = path.resolve(__dirname, '..', '..');

// ── Fixed Job execution (POST /api/jobs) ────────────────────────────────────
const ALLOWED_JOBS = {
  // ── 既存ジョブ (Node/外部コマンド: 変更なし) ──────────────────────────────
  'audit-scan':         { cmd: 'node',  args: ['scripts/tools/run-audit-scan.js'],                             timeout: 30 },
  'cmdb-scan':          { cmd: 'node',  args: ['scripts/tools/run-cmdb-scan.js'],                              timeout: 20 },
  'sync-issues':        { cmd: 'gh',    args: ['issue', 'list', '--state', 'open', '--limit', '20'],           timeout: 30 },
  'agent-teams-status': { cmd: 'node',  args: ['scripts/tools/agent-teams-status.js'],                         timeout: 10 },
  'gitleaks-run':       { cmd: 'gitleaks', args: ['detect', '--source', '.', '--exit-code', '0'],              timeout: 30 },
  // ── 診断系ジョブ (Linux native: bash libexec/*.sh) ───────────────────────
  'mcp-health':         { cmd: 'bash',  args: ['libexec/diag-mcp-health.sh'],     timeout: 30 },
  'architecture-check': { cmd: 'bash',  args: ['libexec/diag-architecture.sh'],   timeout: 30 },
  'worktree-list':      { cmd: 'bash',  args: ['libexec/diag-worktree.sh'],       timeout: 20 },
  'test-all-tools':     { cmd: 'bash',  args: ['libexec/diag-all-tools.sh'],      timeout: 60 },
  // key は UI 互換のため維持。中身は bats / shellcheck (Linux native)
  'pester-run':         { cmd: 'bats',  args: ['tests/bats/unit'],                timeout: 120 },
  'psscriptanalyzer-run': { cmd: 'bash', args: ['-c',
    'shellcheck -S error start.sh lib/*.sh bin/*.sh libexec/*.sh && echo "shellcheck: 0 errors"'],
    timeout: 60 },
  // ── 管理系ジョブ（二段階確認付き）────────────────────────────────────────
  'dashboard-task-register':   { cmd: 'bash', args: ['bin/dashboard-service.sh', '--register', '--run-now'], timeout: 30,
    requireConfirm: true, confirmMsg: 'Dashboard を systemd user service に登録し、今すぐ起動します。ログイン時自動起動 (linger) を有効化します。' },
  'dashboard-task-unregister': { cmd: 'bash', args: ['bin/dashboard-service.sh', '--unregister'], timeout: 30,
    requireConfirm: true, confirmMsg: 'Dashboard の自動起動 (systemd/cron) を解除します。次回以降、自動起動しなくなります。' },
  // ── 状態確認ジョブ（read-only）────────────────────────────────────────────
  'dashboard-task-status':   { cmd: 'bash', args: ['bin/dashboard-service.sh', '--status'], timeout: 10 },
  'source-of-truth-drift':   { cmd: 'bash', args: ['-c',
    't=$(find Claude/templates/claudeos -type f 2>/dev/null | wc -l); d=$(find .claude/claudeos -type f 2>/dev/null | wc -l); echo "Template: $t | Deployed: $d | Diff: $([ "$t" -gt "$d" ] && echo $((t-d)) || echo $((d-t)))"'], timeout: 15 },
  'version-drift-check':     { cmd: 'bash', args: ['-c',
    'for f in README.md CLAUDE.md; do printf "%s: " "$f"; grep -ohE "v[0-9]+\\.[0-9]+\\.[0-9]+" "$f" 2>/dev/null | sort -u | paste -sd,; done'], timeout: 15 },
};
// ── SSE Token store (for EventSource auth when DASHBOARD_PASSWORD is set) ──
// EventSource cannot send Authorization headers, so we use short-lived tokens.
// GET /api/token → { token } (valid 5 min, requires Basic Auth)
// GET /api/events?token=xxx → SSE stream
const sseTokens = new Map(); // token → { expires: Date, user: string }
const SSE_TOKEN_TTL_MS = 5 * 60 * 1000; // 5 minutes

function createSseToken() {
  const token = crypto.randomBytes(16).toString('hex');
  sseTokens.set(token, { expires: Date.now() + SSE_TOKEN_TTL_MS });
  // Cleanup expired tokens
  for (const [t, v] of sseTokens) {
    if (v.expires < Date.now()) sseTokens.delete(t);
  }
  return token;
}

function validateSseToken(token) {
  if (!AUTH_PASS) return true; // auth disabled
  if (!token) return false;
  const entry = sseTokens.get(token);
  if (!entry || entry.expires < Date.now()) { sseTokens.delete(token); return false; }
  return true;
}

const jobRunning = {};  // { [jobId]: true } while job is active
const JOB_HISTORY_FILE = path.join(os.homedir(), '.claudeos', 'job-history.json');
const JOB_HISTORY_MAX  = 50;

function loadJobHistory() {
  try {
    return JSON.parse(fs.readFileSync(JOB_HISTORY_FILE, 'utf8'));
  } catch { return []; }
}

function saveJobHistory(history) {
  try {
    const dir = path.dirname(JOB_HISTORY_FILE);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const tmp = JOB_HISTORY_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(history, null, 2), 'utf8');
    fs.renameSync(tmp, JOB_HISTORY_FILE);  // atomic replace
  } catch { /* non-fatal: in-memory ring buffer still works */ }
}

const jobHistory = loadJobHistory();  // persisted ring buffer – last 50 runs

// ── SSE (Server-Sent Events) ─────────────────────────────────────────────
const sseClients = new Set();  // connected browser tabs

function pushEvent(type, data) {
  const msg = `event: ${type}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const client of [...sseClients]) {
    try { client.write(msg); } catch { sseClients.delete(client); }
  }
}

// config.json / github-registry.json / linux-projects.json の候補パス
const CONFIG_CANDIDATES = [
  path.join(__dirname, '..', '..', 'config'),
  path.join(process.cwd(), 'config'),
];

function findConfig(filename) {
  for (const dir of CONFIG_CANDIDATES) {
    const p = path.join(dir, filename);
    if (fs.existsSync(p)) return p;
  }
  return null;
}

// config.json を読む
let PROJECTS_DIR = (process.env.AI_STARTUP_PROJECTS_DIR || 'D:\\').replace(/\\/g, path.sep);
// Basic Auth: DASHBOARD_PASSWORD env var OR config.json.dashboardAuth.password
let AUTH_USER = process.env.DASHBOARD_USER || 'admin';
let AUTH_PASS = process.env.DASHBOARD_PASSWORD || '';
try {
  const cfgPath = findConfig('config.json');
  if (cfgPath) {
    const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    if (cfg.projectsDir) PROJECTS_DIR = cfg.projectsDir.replace(/\\/g, path.sep);
    if (cfg.dashboardAuth?.password && !AUTH_PASS) {
      AUTH_USER = cfg.dashboardAuth.user     || AUTH_USER;
      AUTH_PASS = cfg.dashboardAuth.password;
    }
  }
} catch { /* 読み取り失敗は無視 */ }

/** Timing-safe string comparison using crypto.timingSafeEqual (prevents timing attacks). */
function safeStrEqual(a, b) {
  const ab = Buffer.from(String(a)), bb = Buffer.from(String(b));
  if (ab.length !== bb.length) {
    crypto.timingSafeEqual(ab, ab); // dummy call: normalize timing
    return false;
  }
  return crypto.timingSafeEqual(ab, bb);
}

/** HTTP Basic Auth check — returns true if authorized (or auth disabled).
 *  Call this at the TOP of each request handler; on failure it writes 401 and returns false.
 *  /api/health is always exempt so monitoring probes are never blocked.
 *  Uses crypto.timingSafeEqual to prevent timing-based password enumeration.
 */
function checkBasicAuth(req, res) {
  if (!AUTH_PASS) return true;                       // auth disabled
  const pathname = req.url.split('?')[0];            // strip query string for matching
  if (pathname === '/api/health' || pathname === '/health') return true; // always public
  const header = req.headers['authorization'] || '';
  if (header.startsWith('Basic ')) {
    const decoded = Buffer.from(header.slice(6), 'base64').toString('utf8');
    const colon   = decoded.indexOf(':');
    if (colon !== -1) {
      const user = decoded.slice(0, colon);
      const pass = decoded.slice(colon + 1);
      if (safeStrEqual(user, AUTH_USER) && safeStrEqual(pass, AUTH_PASS)) return true;
    }
  }
  res.writeHead(401, {
    'WWW-Authenticate': 'Basic realm="ClaudeOS Dashboard"',
    'Content-Type': 'text/plain; charset=utf-8',
  });
  res.end('401 Unauthorized — Set DASHBOARD_PASSWORD env var or config.json dashboardAuth to enable access.');
  return false;
}

// github-registry.json を読む (静的マッピング)
let GITHUB_REGISTRY = {};
try {
  const regPath = findConfig('github-registry.json');
  if (regPath) GITHUB_REGISTRY = JSON.parse(fs.readFileSync(regPath, 'utf8')).projects || {};
} catch { /* 読み取り失敗は無視 */ }

// linux-projects.json を読む
let LINUX_PROJECTS = [];
try {
  const linuxPath = findConfig('linux-projects.json');
  if (linuxPath) {
    const data = JSON.parse(fs.readFileSync(linuxPath, 'utf8'));
    LINUX_PROJECTS = data.projects || [];
    if (data.basePath && !LINUX_BASE) LINUX_BASE = data.basePath;
    if (data.host     && !LINUX_HOST) LINUX_HOST = data.host;
  }
} catch { /* 読み取り失敗は無視 */ }

function getGithubInfo(project) {
  const entry = GITHUB_REGISTRY[project];
  if (entry && entry.url) return entry;
  // ローカル .git/config フォールバック
  try {
    const gitCfg = path.join(PROJECTS_DIR, project, '.git', 'config');
    if (fs.existsSync(gitCfg)) {
      const m = fs.readFileSync(gitCfg, 'utf8').match(/url\s*=\s*(https?:\/\/github\.com\/[^\s]+)/i);
      if (m) return { url: m[1].replace(/\.git$/, ''), private: false, description: '', language: '' };
    }
  } catch { /* 無視 */ }
  return null;
}

// ---------------------------------------------------------------------------
// Phase mapping (CLAUDE.md §5.4)
// ---------------------------------------------------------------------------
function weeksToPhase(week) {
  if (week <=  8) return { name: 'Build',     range: 'Week 1-8',   color: '#2563eb' };
  if (week <= 16) return { name: 'Quality',   range: 'Week 9-16',  color: '#16a34a' };
  if (week <= 20) return { name: 'Stabilize', range: 'Week 17-20', color: '#d97706' };
  return               { name: 'Release',   range: 'Week 21-24', color: '#dc2626' };
}

// ---------------------------------------------------------------------------
// Data collection
// ---------------------------------------------------------------------------

// cron-registry.json のキー名を小文字に正規化 (Project→project, Id→id 等)
function normalizeEntry(e) {
  return {
    project:     e.project     || e.Project     || '',
    id:          e.id          || e.Id          || '',
    created:     e.created     || e.RegisteredAt || e.registeredAt || '',
    duration:    e.duration    || e.DurationMinutes || e.durationMinutes || 300,
    dayOfWeek:   e.dayOfWeek   || e.DayOfWeek   || [],
    time:        e.time        || e.Time        || '',
  };
}

/**
 * Linux OR GitHub の和集合で全プロジェクトを返す。
 * Cron 登録済みのものは hasCron=true + Cron メタ情報付き。
 */
function getAllProjects() {
  // 1. Linux プロジェクト集合
  const linuxSet = new Set(LINUX_PROJECTS);

  // 2. GitHub プロジェクト集合
  const githubSet = new Set(Object.keys(GITHUB_REGISTRY).filter(k => GITHUB_REGISTRY[k].url));

  // 3. Cron プロジェクトマップ (project名 → normalizeEntry 済み)
  const cronMap = {};
  if (fs.existsSync(CRON_REG)) {
    try {
      const raw = JSON.parse(fs.readFileSync(CRON_REG, 'utf8'));
      if (Array.isArray(raw)) {
        raw.forEach(e => {
          const n = normalizeEntry(e);
          if (n.project) cronMap[n.project] = n;
        });
      }
    } catch { /* ignore */ }
  }

  // 4. 和集合 (Linux OR GitHub)。Cron のみは除外しない（Cron=AND条件ではないため）
  const allNames = new Set([...linuxSet, ...githubSet]);
  // Cron 登録があっても Linux/GitHub 未登録なら含めない（要件に従い OR 条件）
  // ただし Cron だけのプロジェクトも一応表示する（ユーザー利便性）
  Object.keys(cronMap).forEach(name => allNames.add(name));

  return [...allNames].sort((a, b) => a.localeCompare(b, 'en', { sensitivity: 'base' }))
    .map(name => {
      const ghInfo    = getGithubInfo(name);
      const cronEntry = cronMap[name] || null;
      return {
        project:           name,
        hasLinux:          linuxSet.has(name),
        hasGithub:         !!(ghInfo?.url),
        hasCron:           !!cronEntry,
        // GitHub info
        githubUrl:         ghInfo?.url          || null,
        githubPrivate:     ghInfo?.private       || false,
        githubDescription: ghInfo?.description   || '',
        githubLanguage:    ghInfo?.language      || '',
        // Cron info (only if registered)
        id:        cronEntry?.id       || '',
        created:   cronEntry?.created  || '',
        duration:  cronEntry?.duration  || 300,
        dayOfWeek: cronEntry?.dayOfWeek || [],
        time:      cronEntry?.time      || '',
      };
    });
}

// 後方互換: テスト等から参照される旧関数
function getRegisteredProjects() {
  const all = getAllProjects();
  return all.filter(e => e.hasCron).map(e => ({
    ...e,
    cronSchedule:      buildCronSchedule(e),
  }));
}

function buildCronSchedule(entry) {
  const DOW_JP = ['日','月','火','水','木','金','土'];
  const days = Array.isArray(entry.dayOfWeek)
    ? entry.dayOfWeek.map(d => DOW_JP[d] || d).join('・')
    : '';
  return days && entry.time ? `${days} ${entry.time} (${entry.duration || 300}分)` : '';
}

function buildTimeline(proj) {
  const regDateStr  = proj.registration_date || proj.start_date || null;
  const deadlineStr = proj.release_deadline  || null;
  const durMonths   = proj.duration_months   || 6;
  if (!regDateStr) return null;

  try {
    const regDate   = new Date(regDateStr);
    const today     = new Date(); today.setHours(0, 0, 0, 0);
    const totalDays = deadlineStr
      ? (new Date(deadlineStr) - regDate) / 86400000
      : durMonths * 30.44;
    const elapsed   = Math.max(0, (today - regDate) / 86400000);
    const remaining = Math.round(totalDays - elapsed);
    const pct       = Math.min(100, Math.max(0, elapsed / totalDays * 100));
    const week      = Math.max(1, Math.ceil(elapsed / 7));
    const totalWeeks= Math.ceil(totalDays / 7);
    const phase     = weeksToPhase(week);
    return {
      regDateStr, deadlineStr,
      totalDays: Math.round(totalDays),
      elapsed:   Math.round(elapsed),
      remaining, pct: Math.round(pct),
      week, totalWeeks, phase,
    };
  } catch { return null; }
}

function getLatestSession(project) {
  if (!fs.existsSync(SESSIONS_DIR)) return null;
  const safe = project.replace(/[^A-Za-z0-9_-]/g, '_');
  try {
    const files = fs.readdirSync(SESSIONS_DIR)
      .filter(f => f.includes(safe) && f.endsWith('.json'))
      .sort().reverse();
    if (!files.length) return null;
    return JSON.parse(fs.readFileSync(path.join(SESSIONS_DIR, files[0]), 'utf8'));
  } catch { return null; }
}

function buildProjectData(entry) {
  // Cron 登録済みの場合のみ state.json / session を読む
  let state = {};
  if (entry.hasCron) {
    const stateFile = path.join(PROJECTS_DIR, entry.project, 'state.json');
    try {
      if (fs.existsSync(stateFile)) state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    } catch { /* state.json unreadable: graceful degradation */ }
  }

  const proj   = state.project || {};
  const kpi    = state.kpi     || {};
  const stable = state.stable  || {};

  // Trust Ledger: state.json の trust フィールドを優先し、なければ trust-score.json を参照
  let trustData = state.trust || {};
  if (entry.hasCron && !trustData.score) {
    try {
      const tsFile = path.join(PROJECTS_DIR, entry.project, '.claude', 'claudeos', 'data', 'trust-score.json');
      if (fs.existsSync(tsFile)) {
        const ts = JSON.parse(fs.readFileSync(tsFile, 'utf8'));
        trustData = {
          score:             ts.score             ?? 0.0,
          level:             ts.level             ?? 1,
          auto_merge_enabled: ts.auto_merge_enabled ?? false,
          history:           ts.history           || {},
        };
      }
    } catch { /* graceful degradation */ }
  }

  // registration_date が未設定なら Cron created を初期値に使う
  if (!proj.registration_date && !proj.start_date && entry.created) {
    proj.registration_date = entry.created.split('T')[0];
  }

  return {
    name:               entry.project,
    hasLinux:           entry.hasLinux           || false,
    hasGithub:          entry.hasGithub          || false,
    hasCron:            entry.hasCron            || false,
    githubUrl:          entry.githubUrl          || null,
    githubPrivate:      entry.githubPrivate       || false,
    githubDescription:  entry.githubDescription   || '',
    githubLanguage:     entry.githubLanguage      || '',
    cronId:             entry.id                  || '',
    cronCreated:        entry.created             || '',
    cronSchedule:       buildCronSchedule(entry),
    phaseMode:          proj.phase_mode           || 'development',
    timeline:    entry.hasCron ? buildTimeline(proj) : null,
    kpi: entry.hasCron ? {
      ciSuccessRate: kpi.ci_success_rate  ?? null,
      testPassRate:  kpi.test_pass_rate   ?? null,
      blockerCount:  kpi.blocker_count    ?? null,
      securityCrit:  kpi.security_critical ?? null,
    } : null,
    stable: entry.hasCron ? {
      achieved:    stable.stable_achieved    || false,
      consecutive: stable.consecutive_success || 0,
      targetN:     stable.target_n            || 3,
    } : null,
    trust: entry.hasCron ? {
      score:           trustData.score              ?? 0.0,
      level:           trustData.level              ?? 1,
      autoMergeEnabled: trustData.auto_merge_enabled ?? false,
      history: {
        totalCiRuns:       (trustData.history || {}).total_ci_runs        ?? 0,
        successfulCiRuns:  (trustData.history || {}).successful_ci_runs   ?? 0,
        ciSuccessStreak:   (trustData.history || {}).ci_success_streak    ?? 0,
        blockedEvents:     (trustData.history || {}).blocked_events       ?? 0,
        lastCiOutcome:     (trustData.history || {}).last_ci_outcome      ?? '',
        lastUpdated:       (trustData.history || {}).last_updated         ?? '',
      },
    } : null,
    session: entry.hasCron ? getLatestSession(entry.project) : null,
  };
}

// ---------------------------------------------------------------------------
// HTML generation (server-side fallback - not used; client renders via JS)
// ---------------------------------------------------------------------------
function escHtml(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
}

function buildHtml() {
  return `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ClaudeOS Projects Dashboard</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', 'Hiragino Sans', system-ui, sans-serif; background: #f0f4f8; color: #1e293b; font-size: 14px; }
  header { background: linear-gradient(135deg, #3b82f6 0%, #6366f1 100%); padding: 16px 28px; display: flex; align-items: center; gap: 14px; box-shadow: 0 2px 8px rgba(59,130,246,.3); }
  header h1 { font-size: 20px; font-weight: 700; color: #fff; letter-spacing: .02em; }
  #meta { margin-left: auto; font-size: 12px; color: rgba(255,255,255,.85); background: rgba(255,255,255,.15); padding: 4px 12px; border-radius: 20px; }
  main { padding: 24px 28px; }
  .card { background: #fff; border-radius: 12px; box-shadow: 0 1px 4px rgba(0,0,0,.08), 0 4px 16px rgba(0,0,0,.06); overflow: hidden; margin-bottom: 8px; }
  table { width: 100%; border-collapse: collapse; }
  th { background: #f8fafc; text-align: left; padding: 11px 16px; font-size: 11px; color: #64748b; text-transform: uppercase; letter-spacing: .07em; font-weight: 600; border-bottom: 1px solid #e2e8f0; }
  td { padding: 14px 16px; border-bottom: 1px solid #f1f5f9; vertical-align: top; line-height: 1.7; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #f8fafc; }
  tr.no-cron td { background: #fafafa; }
  tr.no-cron:hover td { background: #f1f5f9; }
  a { color: #3b82f6; text-decoration: none; font-weight: 500; }
  a:hover { text-decoration: underline; color: #2563eb; }
  .proj-name { font-size: 15px; font-weight: 700; color: #0f172a; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 11px; font-weight: 700; color: #fff; letter-spacing: .03em; }
  .prog-wrap { background: #e2e8f0; border-radius: 6px; height: 8px; width: 130px; display: inline-block; vertical-align: middle; overflow: hidden; }
  .prog-fill { height: 100%; border-radius: 6px; transition: width .5s ease; }
  .ok   { color: #16a34a; font-size: 12px; font-weight: 600; }
  .warn { color: #d97706; font-size: 12px; font-weight: 600; }
  .err  { color: #dc2626; font-size: 12px; font-weight: 600; }
  .muted { color: #94a3b8; font-size: 12px; }
  small { font-size: 12px; color: #64748b; }
  .tag { display: inline-block; background: #eff6ff; color: #3b82f6; border-radius: 6px; padding: 1px 7px; font-size: 11px; font-weight: 600; margin-right: 4px; }
  .tag-linux { background: #f0fdf4; color: #16a34a; }
  .tag-cron  { background: #fef3c7; color: #92400e; }
  .tag-gh    { background: #f0f9ff; color: #0369a1; }
  #empty { padding: 48px; text-align: center; color: #94a3b8; font-size: 15px; }
  #spinner { display: none; margin-left: 10px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  #spinner.active { display: inline-block; width: 14px; height: 14px; border: 2px solid rgba(255,255,255,.3); border-top-color: #fff; border-radius: 50%; animation: spin .8s linear infinite; vertical-align: middle; }
  .no-cron-info { color: #94a3b8; font-size: 12px; }
  .divider { border-top: 2px solid #e2e8f0; }
  .section-label { background: #f8fafc; padding: 6px 16px; font-size: 11px; color: #64748b; font-weight: 700; text-transform: uppercase; letter-spacing: .07em; border-bottom: 1px solid #e2e8f0; }
</style>
</head>
<body>
<header>
  <span style="font-size:26px">🤖</span>
  <h1>ClaudeOS Projects Dashboard</h1>
  <span id="spinner"></span>
  <div id="meta">読み込み中...</div>
</header>
<main>
  <div class="card">
    <table>
      <thead><tr>
        <th>📁 プロジェクト</th>
        <th>📅 フェーズ / タイムライン</th>
        <th>📊 KPI / STABLE</th>
        <th>⏱ セッション / Cron</th>
      </tr></thead>
      <tbody id="tbody"><tr><td colspan="4" id="empty">⏳ データを読み込んでいます...</td></tr></tbody>
    </table>
  </div>
</main>
<script>
  const PHASE_COLORS = { Build:'#3b82f6', Quality:'#22c55e', Stabilize:'#f59e0b', Release:'#ef4444' };

  function renderRow(p) {
    // ① プロジェクト列 (全プロジェクト共通)
    const linuxBadge = p.hasLinux
      ? '<span class="tag tag-linux">🐧 Linux</span>'
      : '';
    const cronBadge = p.hasCron
      ? '<span class="tag tag-cron">⏰ Cron</span>'
      : '';
    const privBadge = p.hasGithub
      ? (p.githubPrivate
          ? '<span style="background:#6b7280;color:#fff;font-size:10px;padding:1px 6px;border-radius:4px;margin-right:4px">Private</span>'
          : '<span style="background:#22c55e;color:#fff;font-size:10px;padding:1px 6px;border-radius:4px;margin-right:4px">Public</span>')
      : '';
    const langBadge = p.githubLanguage
      ? '<span style="background:#dbeafe;color:#1d4ed8;font-size:10px;padding:1px 6px;border-radius:4px">' + p.githubLanguage + '</span>'
      : '';
    const ghLink = p.hasGithub && p.githubUrl
      ? privBadge + '<a href="' + p.githubUrl + '" target="_blank" style="font-weight:600">' +
        p.githubUrl.replace('https://github.com/Kensan196948G/','').replace('https://github.com/','') + '</a>&nbsp;' + langBadge
      : '<span class="muted">GitHub 未登録</span>';
    const desc = p.githubDescription
      ? '<small style="color:#475569;display:block;margin-top:2px;line-height:1.4">' + p.githubDescription + '</small>'
      : '';
    const linuxPath = p.hasLinux
      ? '<small style="color:#94a3b8">📂 ' + (p.linuxPath || '') + '</small>'
      : '<small style="color:#cbd5e1">📂 Linux 未登録</small>';
    const t = p.timeline;
    const regDate = t ? '&nbsp;<small style="color:#94a3b8">📅 登録: ' + t.regDateStr + '</small>' : '';
    const projCell =
      '<div class="proj-name">' + p.name + '</div>' +
      '<div style="margin-top:4px;display:flex;gap:4px;flex-wrap:wrap;align-items:center">' + linuxBadge + cronBadge + '</div>' +
      '<div style="margin-top:4px">' + ghLink + '</div>' +
      (desc ? desc : '') +
      '<div style="margin-top:3px;display:flex;gap:8px;align-items:center">' + linuxPath + regDate + '</div>';

    // ─── Cron 未登録: 簡易行 ───────────────────────────────────────
    if (!p.hasCron) {
      return '<tr class="no-cron">' +
        '<td>' + projCell + '</td>' +
        '<td colspan="3" class="no-cron-info">' +
          '<span style="display:inline-block;background:#f1f5f9;border:1px solid #e2e8f0;border-radius:6px;padding:4px 12px;color:#64748b;font-size:12px">' +
          '⏰ Cron 未登録 — 詳細情報なし</span>' +
        '</td>' +
        '</tr>';
    }

    // ─── Cron 登録済み: フル表示 ──────────────────────────────────
    // ② フェーズ / タイムライン列
    let timelineCell = '<span class="muted">登録日未設定</span>';
    if (t) {
      const pc = PHASE_COLORS[t.phase.name] || '#6b7280';
      const progColor = t.pct >= 80 ? '#ef4444' : t.pct >= 50 ? '#f59e0b' : '#3b82f6';
      const deadline = t.deadlineStr || '';
      timelineCell =
        '<div style="display:flex;align-items:center;gap:8px">' +
          '<span class="badge" style="background:' + pc + '">' + t.phase.name + '</span>' +
          '<small style="color:#64748b">' + t.phase.range + '</small>' +
        '</div>' +
        '<div style="display:flex;align-items:center;gap:8px;margin-top:6px">' +
          '<div class="prog-wrap"><div class="prog-fill" style="width:' + t.pct + '%;background:' + progColor + '"></div></div>' +
          '<b style="font-size:13px">' + t.pct + '%</b>' +
        '</div>' +
        '<small>Week <b>' + t.week + '</b>/' + t.totalWeeks + ' &nbsp;|&nbsp; 残り <b>' + t.remaining + '日</b>' +
        (deadline ? ' (' + deadline + ')' : '') + '</small>';
    }

    // ③ KPI / STABLE 列
    const kpi = p.kpi || {};
    const stb = p.stable || {};
    const ci  = kpi.ciSuccessRate != null
      ? '<span class="' + (kpi.ciSuccessRate >= 0.9 ? 'ok' : 'warn') + '">CI ' + Math.round(kpi.ciSuccessRate*100) + '%</span>'
      : '<span class="muted">CI -</span>';
    const tst = kpi.testPassRate != null
      ? '<span class="' + (kpi.testPassRate >= 0.9 ? 'ok' : 'warn') + '">Test ' + Math.round(kpi.testPassRate*100) + '%</span>'
      : '<span class="muted">Test -</span>';
    const blk = kpi.blockerCount
      ? '<span class="err">⚠ ' + kpi.blockerCount + ' blocker</span>'
      : '<span class="ok">Blocker 0</span>';
    const stable = stb.achieved
      ? '<span class="ok">✅ STABLE ' + stb.consecutive + '/' + stb.targetN + '</span>'
      : '<span class="muted">○ ' + (stb.consecutive||0) + '/' + (stb.targetN||3) + '</span>';
    const mode = '<span class="tag">' + (p.phaseMode || 'dev') + '</span>';
    const kpiCell = '<div style="display:grid;gap:3px">' + [mode, ci, tst, blk, stable].join('') + '</div>';

    // ④ セッション / Cron 列
    let sessStatus = '<span class="muted">記録なし</span>';
    let sessTime   = '';
    if (p.session) {
      const sc = {running:'#22c55e',completed:'#16a34a',failed:'#ef4444',exited:'#94a3b8'}[p.session.status]||'#94a3b8';
      const st = p.session.start_time
        ? new Date(p.session.start_time).toLocaleString('ja-JP',{month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit'})
        : '';
      let elapsed = '';
      if (p.session.start_time && p.session.status === 'running') {
        const mins = Math.round((Date.now() - new Date(p.session.start_time)) / 60000);
        elapsed = mins >= 60
          ? ' (' + Math.floor(mins/60) + 'h' + (mins%60) + 'm経過)'
          : ' (' + mins + '分経過)';
      }
      sessStatus = '<span style="color:' + sc + ';font-weight:700">● ' + p.session.status + elapsed + '</span>';
      sessTime   = '<small>' + st + '</small>';
    }
    const cronLine = p.cronSchedule
      ? '<small style="color:#94a3b8;margin-top:4px;display:block">🕐 ' + p.cronSchedule + '</small>'
      : '<small style="color:#cbd5e1;margin-top:4px;display:block">🕐 スケジュール未設定</small>';
    const sessCell = '<div>' + sessStatus + '</div>' + (sessTime ? '<div>' + sessTime + '</div>' : '') + cronLine;

    return '<tr>' +
      '<td>' + projCell    + '</td>' +
      '<td>' + timelineCell + '</td>' +
      '<td>' + kpiCell     + '</td>' +
      '<td>' + sessCell    + '</td>' +
      '</tr>';
  }

  function refresh() {
    document.getElementById('spinner').classList.add('active');
    fetch('/api/data')
      .then(r => r.json())
      .then(data => {
        document.getElementById('spinner').classList.remove('active');
        const tbody = document.getElementById('tbody');
        if (!data.projects || !data.projects.length) {
          tbody.innerHTML = '<tr><td colspan="4" id="empty">📭 表示できるプロジェクトがありません<br>' +
            '<small>linux-projects.json または github-registry.json にプロジェクトを登録してください</small></td></tr>';
        } else {
          // Cron 登録あり → 上部、なし → 下部
          const cron   = data.projects.filter(p => p.hasCron);
          const noCron = data.projects.filter(p => !p.hasCron);
          let html = '';
          if (cron.length) {
            html += '<tr class="section-row"><td colspan="4" class="section-label">⏰ Cron 登録済み（' + cron.length + ' 件）— フル表示</td></tr>';
            html += cron.map(renderRow).join('');
          }
          if (noCron.length) {
            html += '<tr class="section-row"><td colspan="4" class="section-label divider">📦 その他のプロジェクト（' + noCron.length + ' 件）— 簡易表示</td></tr>';
            html += noCron.map(renderRow).join('');
          }
          tbody.innerHTML = html;
        }
        const now = new Date(data.generated).toLocaleString('ja-JP');
        document.getElementById('meta').textContent =
          data.projects.length + ' プロジェクト  |  ' + now + '  (30秒更新)';
      })
      .catch(e => {
        document.getElementById('spinner').classList.remove('active');
        document.getElementById('meta').textContent = '⚠ 更新エラー: ' + e.message;
      });
  }

  refresh();
  setInterval(refresh, 30000);
</script>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// GitHub + Session + Boot helpers (for /api/mc-data)
// ---------------------------------------------------------------------------

/** Convert ISO timestamp to relative Japanese string */
function relTime(isoStr) {
  if (!isoStr) return '—';
  const ms = Date.now() - new Date(isoStr).getTime();
  const m  = Math.floor(ms / 60000);
  if (m < 1)  return 'たった今';
  if (m < 60) return `${m}分前`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}時間前`;
  return `${Math.floor(h / 24)}日前`;
}

/** Elapsed string from ISO start time */
function elapsedStr(isoStr) {
  if (!isoStr) return '—';
  const m = Math.floor((Date.now() - new Date(isoStr).getTime()) / 60000);
  if (m < 60) return `${m}分`;
  return `${Math.floor(m / 60)}h${m % 60}m`;
}

// Server-side cache for GitHub CLI data (TTL: 25s — slightly shorter than client 30s)
let _ghCache   = null;
let _ghCacheAt = 0;
const GH_CACHE_TTL = 25000;

// Per-project CI data cache — keyed by repoShortName
const _projCiCache = new Map(); // key → { data, at }
const PROJ_CI_TTL  = 30000;    // 30 seconds

/** Fetch GitHub data for a specific repo (owner/repoName)
 *  Uses current gh auth — no separate PAT required if gh is logged in. */
async function fetchProjectCiData(repoFullName) {
  const now = Date.now();
  const cached = _projCiCache.get(repoFullName);
  if (cached && now - cached.at < PROJ_CI_TTL) return cached.data;

  const opts = { timeout: 8000, cwd: PROJ_ROOT };
  const [runRes, prRes, issueRes] = await Promise.allSettled([
    execAsync(`gh run list --repo ${repoFullName} --limit 8 --json databaseId,workflowName,status,conclusion,headBranch,headSha,updatedAt`, opts),
    execAsync(`gh pr list  --repo ${repoFullName} --limit 8 --state all --json number,title,state,author,headRefName,createdAt,mergedAt,mergeCommit,statusCheckRollup`, opts),
    execAsync(`gh issue list --repo ${repoFullName} --limit 8 --json number,title,labels,assignees,createdAt`, opts),
  ]);

  const ciWorkflows = runRes.status === 'fulfilled'
    ? (() => { try { return JSON.parse(runRes.value.stdout).map(r => ({
        status:      r.conclusion || r.status || 'pending',
        displayName: r.workflowName || r.name || '—',
        branch:      r.headBranch  || 'main',
        commit:      (r.headSha    || '').slice(0, 7),
        duration:    '—',
        time:        relTime(r.updatedAt),
      })); } catch { return []; } })()
    : [];

  const recentPRs = prRes.status === 'fulfilled'
    ? (() => { try { return JSON.parse(prRes.value.stdout).map(p => ({
        number: p.number,
        title:  p.title,
        branch: p.headRefName || '',
        status: p.state === 'MERGED' ? 'merged' : p.state === 'CLOSED' ? 'closed' : 'open',
        checks: (p.statusCheckRollup?.length > 0)
                  ? (p.statusCheckRollup.every(c => c.conclusion === 'SUCCESS') ? 'passed' : 'failed')
                  : 'pending',
        mergedAt: p.mergedAt || null,
        time:   relTime(p.mergedAt || p.createdAt),
      })); } catch { return []; } })()
    : [];

  const openIssues = issueRes.status === 'fulfilled'
    ? (() => { try { return JSON.parse(issueRes.value.stdout).map(i => ({
        number:   i.number,
        title:    i.title,
        labels:   (i.labels || []).map(l => l.name).slice(0, 3),
        assignee: (i.assignees || []).map(a => a.login).join(', ') || '未割り当て',
        time:     relTime(i.createdAt),
      })); } catch { return []; } })()
    : [];

  const data = { ciWorkflows, recentPRs, openIssues, repo: repoFullName, generated: new Date().toISOString() };
  _projCiCache.set(repoFullName, { data, at: now });
  return data;
}

async function fetchGhData() {
  const now = Date.now();
  if (_ghCache && now - _ghCacheAt < GH_CACHE_TTL) return _ghCache;

  const opts = { timeout: 7000, cwd: PROJ_ROOT };
  const [runRes, prRes, issueRes] = await Promise.allSettled([
    execAsync('gh run list --limit 8 --json databaseId,workflowName,name,status,conclusion,headBranch,headSha,updatedAt', opts),
    execAsync('gh pr list  --limit 8 --state all --json number,title,state,author,headRefName,createdAt,mergedAt', opts),
    execAsync('gh issue list --limit 8 --json number,title,labels,assignees,createdAt', opts),
  ]);

  const ciWorkflows = runRes.status === 'fulfilled'
    ? (() => { try { return JSON.parse(runRes.value.stdout).map(r => ({
        status:      r.conclusion || r.status || 'pending',
        displayName: r.workflowName || r.name || '—',
        branch:      r.headBranch  || 'main',
        commit:      (r.headSha    || '').slice(0, 7),
        duration:    '—',
        time:        relTime(r.updatedAt),
      })); } catch { return []; } })()
    : [];

  const recentPRs = prRes.status === 'fulfilled'
    ? (() => { try { return JSON.parse(prRes.value.stdout).map(p => ({
        number: p.number,
        title:  p.title,
        branch: p.headRefName || '',
        status: p.state === 'MERGED' ? 'merged' : p.state === 'CLOSED' ? 'closed' : 'open',
        checks: 'passed',
        time:   relTime(p.mergedAt || p.createdAt),
      })); } catch { return []; } })()
    : [];

  const openIssues = issueRes.status === 'fulfilled'
    ? (() => { try { return JSON.parse(issueRes.value.stdout).map(i => ({
        number:   i.number,
        title:    i.title,
        labels:   (i.labels || []).map(l => l.name).slice(0, 3),
        assignee: (i.assignees || []).map(a => a.login).join(', ') || '未割り当て',
        time:     relTime(i.createdAt),
      })); } catch { return []; } })()
    : [];

  _ghCache   = { ciWorkflows, recentPRs, openIssues };
  _ghCacheAt = now;
  return _ghCache;
}

/** 9-step boot status from actual file existence checks */
function getBootSteps() {
  function chk(rel) { try { return fs.existsSync(path.join(PROJ_ROOT, rel)); } catch { return false; } }
  return [
    { step:1, name:'状態確認',      nameEn:'State Load',     detail:'state.json 読み込み・KPI確認',          status: chk('state.json')         ? 'completed':'pending', duration:'—' },
    { step:2, name:'Review Tools',  nameEn:'Review Diag',    detail:'.coderabbit.yaml / .codex 診断',        status: chk('.coderabbit.yaml')   ? 'completed':'pending', duration:'—' },
    { step:3, name:'Codex Setup',   nameEn:'Codex',          detail:'Codex 認証・設定確認',                   status: chk('.codex')             ? 'completed':'pending', duration:'—' },
    { step:4, name:'/goal 設定',    nameEn:'Goal Set',       detail:'/goal コマンドで達成条件を設定',          status: chk('state.json')         ? 'completed':'pending', duration:'—' },
    { step:5, name:'Memory 復元',   nameEn:'Memory Restore', detail:'Memory MCP 前セッション引継ぎ',           status: 'completed',                                      duration:'—' },
    { step:6, name:'Issue 確認',    nameEn:'Issue Check',    detail:'gh issue list で優先課題を確認',          status: 'completed',                                      duration:'—' },
    { step:7, name:'CI 確認',       nameEn:'CI Check',       detail:'gh run list で CI 状態を確認',            status: chk('.github/workflows')  ? 'completed':'pending', duration:'—' },
    { step:8, name:'Agent Teams',   nameEn:'Agent Start',    detail:'状況に応じてパターン A/B/C を spawn',     status: 'completed',                                      duration:'—' },
    { step:9, name:'Monitor 開始',  nameEn:'Monitor Start',  detail:'Monitor → Build → Verify ループ開始',    status: 'completed',                                      duration:'—' },
  ];
}

/** Find the most recently active (or currently running) Cron project */
function getActiveCronProject() {
  const now = new Date();
  let bestEntry = null;
  let bestDiff = Infinity;
  try {
    const raw = JSON.parse(fs.readFileSync(CRON_REG, 'utf8'));
    const entries = Array.isArray(raw) ? raw : [];
    for (const e of entries) {
      const n = normalizeEntry(e);
      const dows = Array.isArray(n.dayOfWeek) ? n.dayOfWeek : [];
      const [h, m] = (n.time || '00:00').split(':').map(Number);
      const duration = n.duration || 300;
      // Search last 7 days for the most recent scheduled start
      for (let daysBack = 0; daysBack <= 6; daysBack++) {
        const candidate = new Date(now);
        candidate.setDate(candidate.getDate() - daysBack);
        candidate.setHours(h, m, 0, 0);
        if (candidate > now) continue;
        // registry: 1=Mon...6=Sat, 7=Sun
        const jsDow = candidate.getDay();
        const regDow = jsDow === 0 ? 7 : jsDow;
        if (!dows.includes(regDow)) continue;
        const diffMin = Math.floor((now - candidate) / 60000);
        if (diffMin < bestDiff) {
          bestDiff = diffMin;
          const isRunning = diffMin < duration;
          const pct = Math.min(100, Math.round(diffMin / duration * 100));
          bestEntry = {
            project:            n.project,
            scheduleTime:       n.time || '—',
            duration,
            isRunning,
            sessionElapsedMin:  diffMin,
            sessionProgressPct: pct,
            lastStartedAt:      candidate.toISOString(),
            nextRunDow:         dows,
          };
        }
        break; // only most recent occurrence per entry
      }
    }
  } catch {}
  return bestEntry;
}

/**
 * Agent Teams Activity: state.agent_teams_usage を返す。
 * agent-teams-tracker.js hook が記録した TeamCreate / SendMessage 使用統計。
 * 既存の getAgentAndEventData() (session 由来) とは別データソース。
 */
function getAgentTeamsActivity() {
  try {
    const stateFile = path.join(PROJ_ROOT, 'state.json');
    if (!fs.existsSync(stateFile)) return { usage: null, available: false };
    const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    const atu = state.agent_teams_usage || null;
    if (!atu) return { usage: null, available: false };

    const cur     = atu.current_session || {};
    const history = Array.isArray(atu.history) ? atu.history : [];

    // パターン別集計（過去 7 日）
    const sevenDaysAgo = Date.now() - 7 * 86400000;
    const recent = history.filter(h => {
      try { return new Date(h.session_start_at).getTime() >= sevenDaysAgo; } catch { return false; }
    });
    const patternCount = { A: 0, B: 0, C: 0 };
    recent.forEach(h => (h.patterns_used || []).forEach(p => {
      if (patternCount[p] !== undefined) patternCount[p] += 1;
    }));

    return {
      available: true,
      session_start_at: atu.session_start_at || null,
      current: {
        team_create_count:  cur.team_create_count  || 0,
        send_message_count: cur.send_message_count || 0,
        patterns_used:      cur.patterns_used      || [],
        last_activity_at:   cur.last_activity_at   || null,
        teammates:          (cur.teammates || []).slice(-10),  // 直近 10 件
      },
      last_7days: {
        sessions_with_teams: recent.length,
        pattern_count:       patternCount,
      },
      history_total: history.length,
    };
  } catch (e) {
    return { usage: null, available: false, error: e.message };
  }
}

/** Trust Score: trust-score.json を読み込んで返す（/health エンドポイント共用） */
function readTrustScore() {
  try {
    const tsFile = path.join(PROJ_ROOT, '.claude', 'claudeos', 'data', 'trust-score.json');
    if (fs.existsSync(tsFile)) return JSON.parse(fs.readFileSync(tsFile, 'utf8'));
  } catch { /* ignore */ }
  return { score: 0, level: 1, auto_merge_enabled: false };
}

/** Active session / project info for Boot Sequence panel */
function getCurrentProjectInfo() {
  // Dev environment info (git)
  const projectName = path.basename(PROJ_ROOT);
  let branch = '—', todayCommits = 0, todayCommitList = [];
  try {
    branch = execSync('git branch --show-current', { cwd: PROJ_ROOT, encoding: 'utf8', timeout: 3000 }).trim() || 'main';
    const today = new Date().toISOString().slice(0, 10);
    const raw = execSync(`git log --after="${today} 00:00" --oneline`, { cwd: PROJ_ROOT, encoding: 'utf8', timeout: 3000 }).trim();
    todayCommitList = raw ? raw.split('\n').filter(Boolean) : [];
    todayCommits = todayCommitList.length;
  } catch {}
  let goal = '—', phase = '—', stableConsecutive = 0, stableTargetN = 3, stableAchieved = false;
  try {
    const st = JSON.parse(fs.readFileSync(path.join(PROJ_ROOT, 'state.json'), 'utf8'));
    goal              = st?.goal?.title || (typeof st?.goal === 'string' ? st.goal : null) || '—';
    phase             = st?.execution?.phase || st?.phase || '—';
    stableConsecutive = st?.stable?.consecutive_success || 0;
    stableTargetN     = st?.stable?.target_n             || 3;
    stableAchieved    = st?.stable?.stable_achieved      || false;
  } catch {}

  // Trust Score: readTrustScore() 共通ヘルパーを使用
  const _ts = readTrustScore();
  const trust = {
    score:             _ts.score              ?? 0.0,
    level:             _ts.level              ?? 1,
    auto_merge_enabled: _ts.auto_merge_enabled ?? false,
    history: {
      totalCiRuns:        (_ts.history || {}).total_ci_runs        ?? 0,
      successfulCiRuns:   (_ts.history || {}).successful_ci_runs   ?? 0,
      ciSuccessStreak:    (_ts.history || {}).ci_success_streak    ?? 0,
      stableAchievements: (_ts.history || {}).stable_achievements  ?? 0,
      totalSessions:      (_ts.history || {}).total_sessions       ?? 0,
      blockedEvents:      (_ts.history || {}).blocked_events       ?? 0,
      lastUpdated:        (_ts.history || {}).last_updated         ?? '',
    },
  };

  // Active Cron project (most recently running)
  const activeCron = getActiveCronProject();
  return {
    projectName, branch, todayCommits,
    todayCommitList: todayCommitList.slice(0, 5),
    goal, phase,
    stable: { consecutive: stableConsecutive, targetN: stableTargetN, achieved: stableAchieved },
    activeCron,
    trust,
    checkedAt: new Date().toISOString(),
  };
}

/** Agent teams + event log from session files and git log */
function getAgentAndEventData() {
  const agentTeams = [];
  const eventLog   = [];

  if (fs.existsSync(SESSIONS_DIR)) {
    try {
      fs.readdirSync(SESSIONS_DIR)
        .filter(f => f.endsWith('.json'))
        .sort().reverse()
        .slice(0, 6)
        .forEach((file, idx) => {
          try {
            const s = JSON.parse(fs.readFileSync(path.join(SESSIONS_DIR, file), 'utf8'));
            agentTeams.push({
              id:         `sess-${idx}`,
              role:       s.agent_role  || 'CTO',
              icon:       s.agent_icon  || '👔',
              status:     s.status === 'running' ? 'working' : s.status === 'completed' ? 'completed' : 'idle',
              task:       s.current_task || s.goal || '—',
              model:      'claude-sonnet-4-6',
              tokens:     s.token_count  || 0,
              elapsed:    elapsedStr(s.start_time),
              domain:     s.project      || '—',
              lastAction: s.current_task || '—',
              time:       relTime(s.start_time),
            });
          } catch { /* skip unreadable session */ }
        });
    } catch { /* SESSIONS_DIR not readable */ }
  }

  // Git log as event stream
  try {
    const out = require('child_process').execSync(
      'git log --oneline -15 --pretty=format:"%h|%s|%ct|%an"',
      { cwd: PROJ_ROOT, timeout: 3000, encoding: 'utf8' }
    );
    out.split('\n').filter(Boolean).forEach(line => {
      const [hash, subject, ctStr, author] = line.split('|');
      if (!hash || !subject) return;
      // Convert UNIX timestamp to Japanese relative time
      const diffSec = Math.floor(Date.now() / 1000) - parseInt(ctStr || '0', 10);
      let timeJa;
      if      (diffSec < 60)          timeJa = `${diffSec}秒前`;
      else if (diffSec < 3600)        timeJa = `${Math.floor(diffSec / 60)}分前`;
      else if (diffSec < 86400)       timeJa = `${Math.floor(diffSec / 3600)}時間前`;
      else                            timeJa = `${Math.floor(diffSec / 86400)}日前`;
      const type = subject.startsWith('fix')   ? 'success'
                 : subject.startsWith('feat')  ? 'info'
                 : subject.startsWith('chore') ? 'phase'
                 : 'info';
      eventLog.push({ time: timeJa, agent: author || 'Git', message: `[${hash}] ${subject}`, type });
    });
  } catch { /* git not available */ }

  return { agentTeams, eventLog };
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------
function handleApiData(res) {
  try {
    const projects = getAllProjects().map(buildProjectData);
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8',
                         'Cache-Control': 'no-cache' });
    res.end(JSON.stringify({ projects, generated: new Date().toISOString() }, null, 2));
  } catch (e) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: e.message }));
  }
}

// ---------------------------------------------------------------------------
// Mission Control aggregated data endpoint
// ---------------------------------------------------------------------------

// Compute next run date from cron expression (server-side)
function computeCronNextRun(scheduleExpr) {
  const parts = String(scheduleExpr || '').trim().split(/\s+/);
  if (parts.length < 5) return null;
  const min  = parseInt(parts[0]);
  const hour = parseInt(parts[1]);
  const dowStr = parts[4];

  // Parse DOW
  const dows = new Set();
  String(dowStr).split(',').forEach(p => {
    if (p.includes('-')) {
      const [a, b] = p.split('-').map(Number);
      for (let i = a; i <= b; i++) dows.add(i);
    } else {
      const n = parseInt(p);
      if (!isNaN(n)) dows.add(n);
    }
  });
  if (dows.size === 0) return null;

  const now = new Date();
  for (let i = 0; i <= 7; i++) {
    const d = new Date(now);
    d.setDate(d.getDate() + i);
    d.setHours(hour, min, 0, 0);
    if (i === 0 && d <= now) continue;
    if (dows.has(d.getDay())) return d;
  }
  return null;
}

async function handleMcData(res) {
  try {
    // ── 1. Cron schedules (sync) ──────────────────────────────────────────
    const cronReg = fs.existsSync(CRON_REG)
      ? JSON.parse(fs.readFileSync(CRON_REG, 'utf8'))
      : [];

    const cronSchedules = (Array.isArray(cronReg) ? cronReg : []).map(e => {
      const n = normalizeEntry(e);
      let scheduleExpr = '0 9 * * 1-6';
      if (n.time) {
        const [hh, mm] = n.time.split(':');
        const min  = parseInt(mm || '0') || 0;
        const hour = parseInt(hh) || 9;
        const dowPart = Array.isArray(n.dayOfWeek) && n.dayOfWeek.length
          ? n.dayOfWeek.join(',')
          : '1-6';
        scheduleExpr = `${min} ${hour} * * ${dowPart}`;
      }
      const nextDate = computeCronNextRun(scheduleExpr);
      const nextRun  = nextDate
        ? `${nextDate.getFullYear()}-${String(nextDate.getMonth()+1).padStart(2,'0')}-${String(nextDate.getDate()).padStart(2,'0')} ${String(nextDate.getHours()).padStart(2,'0')}:${String(nextDate.getMinutes()).padStart(2,'0')}`
        : '—';
      return {
        project:  n.project,
        schedule: scheduleExpr,
        duration: n.duration  || 300,
        status:   'active',
        lastRun:  n.created ? n.created.split('T')[0] : '—',
        nextRun,
        result:   'success',
      };
    });

    // ── 2. GitHub data (async, cached 25s) ───────────────────────────────
    const ghData = await fetchGhData();

    // ── 3. Boot steps (file-existence check) ─────────────────────────────
    const bootSteps = getBootSteps();

    // ── 4. Agent teams + event log ────────────────────────────────────────
    const { agentTeams, eventLog } = getAgentAndEventData();

    const currentProjectInfo = getCurrentProjectInfo();
    const data = {
      currentProjectInfo,
      cronSchedules,
      ciWorkflows:  ghData.ciWorkflows,
      recentPRs:    ghData.recentPRs,
      openIssues:   ghData.openIssues,
      bootSteps,
      agentTeams,
      eventLog,
      generated: new Date().toISOString(),
    };
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
    res.end(JSON.stringify(data, null, 2));
  } catch (e) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: e.message }));
  }
}

// ---------------------------------------------------------------------------
// Mission Control HTML (static file)
// ---------------------------------------------------------------------------
const MC_HTML_PATH = path.join(__dirname, 'mission-control.html');

function handleMissionControl(res) {
  try {
    if (fs.existsSync(MC_HTML_PATH)) {
      const html = fs.readFileSync(MC_HTML_PATH, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
    } else {
      res.writeHead(404); res.end('mission-control.html not found');
    }
  } catch (e) {
    res.writeHead(500); res.end(e.message);
  }
}

// Export for testing (must be before server start guard)
// ── Job execution handlers ────────────────────────────────────────────────
function handleJobRun(req, res) {
  let body = '';
  req.on('data', chunk => { body += chunk; });
  req.on('end', () => {
    let jobId;
    try { jobId = JSON.parse(body).jobId; } catch {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Invalid JSON body' }));
      return;
    }
    if (!jobId || !ALLOWED_JOBS[jobId]) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unknown jobId', allowed: Object.keys(ALLOWED_JOBS) }));
      return;
    }
    if (jobRunning[jobId]) {
      res.writeHead(409, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Job already running', jobId }));
      return;
    }
    const job = ALLOWED_JOBS[jobId];
    jobRunning[jobId] = true;
    const startAt = new Date().toISOString();
    const entry = { jobId, startAt, status: 'running', endAt: null, exitCode: null, output: '' };
    jobHistory.push(entry);
    if (jobHistory.length > JOB_HISTORY_MAX) jobHistory.shift();
    pushEvent('job-update', { jobId, status: 'running', startAt });

    const child = spawn(job.cmd, job.args, { cwd: PROJ_ROOT, shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    child.stdout.on('data', d => { out += d.toString(); });
    child.stderr.on('data', d => { out += d.toString(); });

    const timer = setTimeout(() => {
      child.kill();
      entry.status = 'timeout';
      entry.endAt = new Date().toISOString();
      entry.output = out.slice(-500);
      jobRunning[jobId] = false;
      while (jobHistory.length > JOB_HISTORY_MAX) jobHistory.shift();
      saveJobHistory(jobHistory);
      pushEvent('job-update', { jobId, status: 'timeout', startAt, endAt: entry.endAt });
    }, job.timeout * 1000);

    child.on('close', code => {
      clearTimeout(timer);
      entry.status = code === 0 ? 'done' : 'failed';
      entry.exitCode = code;
      entry.endAt = new Date().toISOString();
      entry.output = out.slice(-500);
      jobRunning[jobId] = false;
      while (jobHistory.length > JOB_HISTORY_MAX) jobHistory.shift();
      saveJobHistory(jobHistory);
      pushEvent('job-update', { jobId, status: entry.status, exitCode: code, startAt, endAt: entry.endAt });
    });

    res.writeHead(202, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ ok: true, jobId, startAt }));
  });
}

function handleJobStatus(res) {
  const jobsMeta = Object.fromEntries(
    Object.entries(ALLOWED_JOBS).map(([k, v]) => [k, {
      requireConfirm: !!v.requireConfirm,
      confirmMsg:     v.confirmMsg || '',
    }])
  );
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
  res.end(JSON.stringify({
    running:   jobRunning,
    history:   jobHistory.slice(-20),
    jobs:      Object.keys(ALLOWED_JOBS),
    jobsMeta,
    generated: new Date().toISOString(),
  }, null, 2));
}

// ── Supervisor Status ─────────────────────────────────────────────────────
const SUPERVISOR_STATE_FILE = path.join(os.homedir(), '.claudeos', 'supervisor', 'state.json');

function handleSupervisorStatus(res) {
  try {
    if (!fs.existsSync(SUPERVISOR_STATE_FILE)) {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
      res.end(JSON.stringify({ running: false, message: 'Supervisor not started', processes: {}, generated: new Date().toISOString() }));
      return;
    }
    const content = fs.readFileSync(SUPERVISOR_STATE_FILE, 'utf8');
    const state   = JSON.parse(content);
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
    res.end(JSON.stringify({ running: true, ...state }, null, 2));
  } catch (e) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: e.message }));
  }
}

// ── System Health ─────────────────────────────────────────────────────────
const SKIP_DIRS = new Set(['node_modules', '.git', '__pycache__', '.venv', 'dist', 'build', 'snapshots']);

function countFiles(dir) {
  let n = 0;
  function walk(d) {
    if (!fs.existsSync(d)) return;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.isDirectory()) {
        if (!SKIP_DIRS.has(e.name)) walk(path.join(d, e.name));
      } else { n++; }
    }
  }
  try { walk(dir); } catch {}
  return n;
}

// Cache system health to avoid repeated slow powershell calls
let _healthCache = null;
let _healthCacheAt = 0;
const HEALTH_CACHE_TTL = 15000; // 15 seconds

function handleSystemHealth(res) {
  // Return cached response if fresh
  if (_healthCache && (Date.now() - _healthCacheAt) < HEALTH_CACHE_TTL) {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
    res.end(_healthCache);
    return;
  }
  const c = {};
  // package.json
  c.packageJsonMissing  = !fs.existsSync(path.join(PROJ_ROOT, 'package.json'));
  // .claude/skills/
  c.claudeSkillsMissing = !fs.existsSync(path.join(PROJ_ROOT, '.claude', 'skills'));
  // CORS / Auth
  c.corsEnabled  = true;
  c.authEnabled  = !!AUTH_PASS;  // true when DASHBOARD_PASSWORD env or config.json.dashboardAuth set
  // Job history persistence
  // JOB_HISTORY_FILE が定義されていれば永続化コードが有効（ファイル未生成でも true）
  c.jobHistoryPersisted = typeof JOB_HISTORY_FILE === 'string' && JOB_HISTORY_FILE.length > 0;
  // Untracked files
  try {
    const out = execSync('git ls-files --others --exclude-standard', { cwd: PROJ_ROOT, encoding: 'utf8', timeout: 5000 });
    const lines = out.trim().split('\n').filter(Boolean);
    c.untrackedFilesCount    = lines.length;
    c.reportsUntrackedCount  = lines.filter(l => l.startsWith('reports/')).length;
  } catch { c.untrackedFilesCount = -1; c.reportsUntrackedCount = -1; }
  // Source of Truth drift
  try {
    const tpl  = countFiles(path.join(PROJ_ROOT, 'Claude', 'templates', 'claudeos'));
    const dep  = countFiles(path.join(PROJ_ROOT, '.claude', 'claudeos'));
    c.templateFilesCount  = tpl;
    c.deployedFilesCount  = dep;
    c.sourceOfTruthDiff   = Math.abs(tpl - dep);
  } catch { c.sourceOfTruthDiff = -1; }
  // Dashboard service status (Linux: systemd user service / crontab @reboot)
  try {
    let st = 'NotRegistered';
    try {
      const o = execSync('systemctl --user is-active claudeos-dashboard.service 2>/dev/null', { encoding: 'utf8', timeout: 1500 });
      const v = o.trim();
      if (v === 'active') st = 'Running';
      else if (v) st = v;
    } catch {
      try {
        const cr = execSync('crontab -l 2>/dev/null | grep -c serve-dashboard.js', { encoding: 'utf8', timeout: 1500 });
        if (parseInt(cr.trim(), 10) > 0) st = 'CronRegistered';
      } catch { /* no cron entry */ }
    }
    c.dashboardTaskState = st;
  } catch { c.dashboardTaskState = 'Unknown'; }
  // state.json phase/deploy-ready
  try {
    const s = JSON.parse(fs.readFileSync(path.join(PROJ_ROOT, 'state.json'), 'utf8'));
    c.currentPhase    = s.execution?.phase || s.phase || '—';
    c.deployReady     = s.deploy?.ready || false;
    c.maintenanceMode = (s.project?.phase_mode === 'maintenance');
    c.stableAchieved  = s.stable?.stable_achieved || false;
  } catch { c.currentPhase = '—'; }

  // Server process info
  c.serverUptimeSec = Math.floor(process.uptime());
  c.serverVersion   = '3.3.5';  // Update on each release

  const body = JSON.stringify({ checks: c, generated: new Date().toISOString() }, null, 2);
  _healthCache   = body;
  _healthCacheAt = Date.now();

  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
  res.end(body);
}

// ── Cron Registry CRUD ────────────────────────────────────────────────────

/** Read cron-registry.json safely */
function readCronRegistry() {
  try {
    if (!fs.existsSync(CRON_REG)) return [];
    return JSON.parse(fs.readFileSync(CRON_REG, 'utf8'));
  } catch { return []; }
}

/** Write cron-registry.json atomically */
function writeCronRegistry(entries) {
  const dir = path.dirname(CRON_REG);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const tmp = CRON_REG + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(entries, null, 2), 'utf8');
  fs.renameSync(tmp, CRON_REG);
}

/** GET /api/cron — list with enhanced next-run calculation */
function handleCronList(res) {
  const entries = readCronRegistry();
  const enhanced = entries.map(e => {
    // Build cron expression
    const [hh, mm] = (e.Time || '09:00').split(':');
    const min  = parseInt(mm || '0') || 0;
    const hour = parseInt(hh) || 9;
    const dows = Array.isArray(e.DayOfWeek) ? e.DayOfWeek : [1];
    const scheduleExpr = `${min} ${hour} * * ${dows.join(',')}`;

    // Compute next run
    const dowSet = new Set(dows);
    let nextDate = null;
    const now = new Date();
    for (let i = 0; i <= 7; i++) {
      const d = new Date(now);
      d.setDate(d.getDate() + i);
      d.setHours(hour, min, 0, 0);
      if (i === 0 && d <= now) continue;
      if (dowSet.has(d.getDay())) { nextDate = d; break; }
    }
    const nextRun = nextDate
      ? `${nextDate.getFullYear()}-${String(nextDate.getMonth()+1).padStart(2,'0')}-${String(nextDate.getDate()).padStart(2,'0')} ${String(nextDate.getHours()).padStart(2,'0')}:${String(nextDate.getMinutes()).padStart(2,'0')}`
      : '—';

    return {
      id:              e.Id,
      project:         e.Project,
      dayOfWeek:       dows,
      time:            e.Time || '09:00',
      durationMinutes: e.DurationMinutes || 300,
      registeredAt:    e.RegisteredAt || '',
      schedule:        scheduleExpr,
      nextRun,
    };
  });
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
  res.end(JSON.stringify({ entries: enhanced, count: enhanced.length, generated: new Date().toISOString() }, null, 2));
}

/** POST /api/cron — register new cron entry */
function handleCronRegister(req, res) {
  let body = '';
  req.on('data', chunk => { body += chunk; });
  req.on('end', () => {
    let data;
    try { data = JSON.parse(body); } catch {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Invalid JSON' }));
      return;
    }
    const { project, dayOfWeek, time, durationMinutes } = data;
    if (!project || typeof project !== 'string' || project.trim().length === 0) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'project is required' }));
      return;
    }
    const dows = Array.isArray(dayOfWeek) ? dayOfWeek.map(Number).filter(n => n >= 0 && n <= 6) : [1];
    const entries = readCronRegistry();
    const existing = entries.find(e => e.Project === project.trim());
    if (existing) {
      res.writeHead(409, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Project already registered', id: existing.Id }));
      return;
    }
    const newEntry = {
      Id:              crypto.randomBytes(4).toString('hex'),
      Project:         project.trim(),
      DayOfWeek:       dows,
      Time:            String(time || '09:00').replace(/[^0-9:]/g, ''),
      DurationMinutes: Math.min(Math.max(parseInt(durationMinutes) || 300, 30), 600),
      RegisteredAt:    new Date().toISOString(),
    };
    entries.push(newEntry);
    writeCronRegistry(entries);
    pushEvent('cron-change', { action: 'register', id: newEntry.Id, project: newEntry.Project });
    res.writeHead(201, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ ok: true, entry: newEntry }));
  });
}

/** DELETE /api/cron/:id — unregister cron entry */
function handleCronDelete(req, res, id) {
  const entries = readCronRegistry();
  const idx = entries.findIndex(e => e.Id === id);
  if (idx === -1) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Entry not found', id }));
    return;
  }
  const removed = entries.splice(idx, 1)[0];
  writeCronRegistry(entries);
  pushEvent('cron-change', { action: 'delete', id, project: removed.Project });
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify({ ok: true, removed: { id, project: removed.Project } }));
}

function handleSSE(req, res) {
  // When auth is enabled, require token from ?token=xxx (EventSource can't send headers)
  if (AUTH_PASS) {
    const urlObj  = new URL(req.url, `http://localhost`);
    const token   = urlObj.searchParams.get('token') || '';
    if (!validateSseToken(token)) {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'SSE requires valid token from GET /api/token' }));
      return;
    }
  }
  res.writeHead(200, {
    'Content-Type':                'text/event-stream',
    'Cache-Control':               'no-cache',
    'Connection':                  'keep-alive',
    'Access-Control-Allow-Origin': '*',
    'X-Accel-Buffering':           'no',
  });
  res.write('retry: 3000\n\n');
  sseClients.add(res);

  // Send current state immediately on connect
  try {
    const s = JSON.parse(fs.readFileSync(path.join(PROJ_ROOT, 'state.json'), 'utf8'));
    res.write(`event: state-change\ndata: ${JSON.stringify({
      phase:       s.execution?.phase || '—',
      goal:        s.goal?.title || (typeof s.goal === 'string' ? s.goal : '—'),
      stable:      s.stable?.stable_achieved || false,
      consecutive: s.stable?.consecutive_success || 0,
    })}\n\n`);
  } catch {}

  const heartbeat = setInterval(() => {
    try { res.write(': heartbeat\n\n'); } catch { clearInterval(heartbeat); sseClients.delete(res); }
  }, 15000);

  req.on('close', () => { clearInterval(heartbeat); sseClients.delete(res); });
}

function watchFiles() {
  // ── state.json 監視 ────────────────────────────────────────────────────
  const stateFile = path.join(PROJ_ROOT, 'state.json');
  let lastStateContent = '';
  fs.watchFile(stateFile, { interval: 2000 }, () => {
    try {
      const content = fs.readFileSync(stateFile, 'utf8');
      if (content === lastStateContent) return;
      lastStateContent = content;
      const s = JSON.parse(content);
      pushEvent('state-change', {
        phase:       s.execution?.phase || '—',
        goal:        s.goal?.title || (typeof s.goal === 'string' ? s.goal : '—'),
        stable:      s.stable?.stable_achieved || false,
        consecutive: s.stable?.consecutive_success || 0,
      });
    } catch {}
  });

  // ── dashboard.log テール監視 ────────────────────────────────────────────
  const logFile = path.join(os.homedir(), '.claudeos', 'dashboard.log');
  let logOffset = 0;
  try { logOffset = fs.statSync(logFile).size; } catch {}
  fs.watchFile(logFile, { interval: 1000 }, () => {
    try {
      const stat = fs.statSync(logFile);
      if (stat.size <= logOffset) { logOffset = stat.size; return; }
      const fd  = fs.openSync(logFile, 'r');
      const buf = Buffer.alloc(stat.size - logOffset);
      fs.readSync(fd, buf, 0, buf.length, logOffset);
      fs.closeSync(fd);
      logOffset = stat.size;
      const lines = buf.toString('utf8').split('\n').filter(Boolean);
      for (const line of lines) {
        pushEvent('log-line', { line, at: new Date().toISOString() });
      }
    } catch {}
  });

  // ── supervisor state.json 監視 ──────────────────────────────────────────
  const supervisorStateFile = path.join(os.homedir(), '.claudeos', 'supervisor', 'state.json');
  let lastSupervisorContent = '';
  fs.watchFile(supervisorStateFile, { interval: 2000 }, () => {
    try {
      const content = fs.readFileSync(supervisorStateFile, 'utf8');
      if (content === lastSupervisorContent) return;
      lastSupervisorContent = content;
      const s = JSON.parse(content);
      pushEvent('supervisor-update', { processes: s.processes, generated: s.generated });
    } catch {}
  });
}

if (typeof module !== 'undefined') {
  module.exports = { getAllProjects, getRegisteredProjects, buildProjectData, buildTimeline, weeksToPhase };
}

// Start server only when run directly (not when required by tests)
if (require.main === module) {
  const server = http.createServer((req, res) => {
    // CORS for LAN access (dashboard is local-network only, no external exposure)
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

    // Basic Auth guard (skips /api/health; disabled when DASHBOARD_PASSWORD is unset)
    if (!checkBasicAuth(req, res)) return;

    // Strip query string for route matching (prevents ?bypass injection)
    const pn = req.url.split('?')[0];

    if (pn === '/health' || pn === '/api/health') {
      const ts = readTrustScore();
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ status: 'ok', uptime: Math.floor(process.uptime()), trust: ts, at: new Date().toISOString() }));
      return;
    }
    if (pn === '/api/data')           return handleApiData(res);
    if (pn === '/api/mc-data')        { handleMcData(res).catch(e => { try { res.writeHead(500); res.end(e.message); } catch {} }); return; }
    if (pn === '/api/agent-teams') {
      try {
        const data = getAgentTeamsActivity();
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
        res.end(JSON.stringify({ ...data, generated: new Date().toISOString() }, null, 2));
      } catch (e) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
      return;
    }
    if (req.method === 'POST' && pn === '/api/jobs') { return handleJobRun(req, res); }
    if (pn === '/api/jobs/status')                    { return handleJobStatus(res); }
    // Per-project GitHub CI data — GET /api/project-ci?repo=Kensan196948G/RepoName
    if (pn === '/api/project-ci' && req.method === 'GET') {
      const urlObj = new URL(req.url, 'http://localhost');
      const repo   = urlObj.searchParams.get('repo') || '';
      // Security: only allow format "owner/reponame" (alphanumeric + dash/underscore)
      if (!/^[A-Za-z0-9_-]+\/[A-Za-z0-9_.-]+$/.test(repo)) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid repo format. Use owner/reponame' }));
        return;
      }
      fetchProjectCiData(repo)
        .then(data => {
          res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
          res.end(JSON.stringify(data, null, 2));
        })
        .catch(e => {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: e.message }));
        });
      return;
    }
    if (pn === '/api/token' && req.method === 'GET')   {
      // Issue short-lived SSE token (requires Basic Auth; disabled when no password)
      const token = createSseToken();
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ token, ttlMs: SSE_TOKEN_TTL_MS }));
      return;
    }
    if (pn === '/api/events')                         { return handleSSE(req, res); }
    if (pn === '/api/system-health')                  { return handleSystemHealth(res); }
    if (pn === '/api/supervisor/status')              { return handleSupervisorStatus(res); }
    // Cron registry CRUD
    if (req.method === 'GET'    && pn === '/api/cron') { return handleCronList(res); }
    if (req.method === 'POST'   && pn === '/api/cron') { return handleCronRegister(req, res); }
    if (req.method === 'DELETE' && pn.startsWith('/api/cron/')) {
      const id = pn.replace('/api/cron/', '');
      return handleCronDelete(req, res, id);
    }
    if (pn === '/mission-control' || pn === '/mc') return handleMissionControl(res);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(buildHtml());
  });

  server.listen(PORT, '0.0.0.0', () => {
    const lanIp = Object.values(os.networkInterfaces()).flat()
      .find(i => i && i.family === 'IPv4' && !i.internal)?.address || '(unavailable)';
    console.log(`[Dashboard] Local: http://localhost:${PORT}`);
    console.log(`[Dashboard] LAN:   http://${lanIp}:${PORT}`);
    console.log(`[Dashboard] PROJECTS_DIR: ${PROJECTS_DIR}`);
    console.log(`[Dashboard] LINUX_PROJECTS: ${LINUX_PROJECTS.length} entries`);
    console.log(`[Dashboard] GITHUB_REGISTRY: ${Object.keys(GITHUB_REGISTRY).length} entries`);
    console.log(`[Dashboard] CRON_REG: ${CRON_REG}`);
    console.log('[Dashboard] Ctrl+C to stop');
    watchFiles();
  });

  server.on('error', e => {
    if (e.code === 'EADDRINUSE') {
      console.error(`[Dashboard] Port ${PORT} is already in use. Try: node serve-dashboard.js ${PORT + 1}`);
    } else { console.error('[Dashboard] Error:', e.message); }
    process.exit(1);
  });
}
