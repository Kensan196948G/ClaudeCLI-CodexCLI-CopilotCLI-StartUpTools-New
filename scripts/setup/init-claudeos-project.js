#!/usr/bin/env node
// init-claudeos-project.js — ClaudeOS を未導入プロジェクトに新規導入する
//
// 背景:
// - migrate-agent-teams.js は既存 ClaudeOS プロジェクトへの *差分配布* 専用で、
//   .claude/claudeos が無いプロジェクトは skip する (例: CivilPDF-DX)。
// - 本スクリプトは TemplateSyncManager.ps1 の Sync-LauncherClaudeGlobalConfig が行う
//   テンプレートマッピングを cross-platform (Node) で忠実再現し、ClaudeOS 構造を *新規導入* する。
//   (正規 init は PowerShell ランチャー結合のため、Linux 単体では使えない)
//
// セマンティクス:
// - copy-if-missing: 既存ファイルは絶対に上書きしない (プロジェクト固有設定を保護)
// - 冪等: 再実行で up-to-date
// - --dry-run でプレビュー / --apply で実行
// - state.json は "YOUR_PROJECT" をターゲット名に置換して seed
// - skills 配置後に .skills-dirty sentinel を touch → 次セッションで reloadSkills 発火
//
// 使い方:
//   node scripts/setup/init-claudeos-project.js --target /path/to/Project --dry-run
//   node scripts/setup/init-claudeos-project.js --project CivilPDF-DX --apply
//   (--project は config/linux-projects.json または config/config.json から解決。.claude 非依存)
//
// 導入後は migrate-agent-teams.js --apply で session-start.js 等を最新化することを推奨。
//
// SSH tip (Linux): 非 TTY では stdout がバッファされ固まって見えるため stdbuf 推奨:
//   ssh host 'cd <repo> && stdbuf -oL -eL node scripts/setup/init-claudeos-project.js --project NAME --dry-run'

const fs   = require("fs");
const path = require("path");

const REPO_ROOT = path.join(__dirname, "..", "..");

// Sync-LauncherClaudeGlobalConfig (TemplateSyncManager.ps1:155-234) のマッピングを再現。
// すべて copy-if-missing。type: "dir" = 再帰コピー / "file" = 単一ファイル。
const MAPPINGS = [
  { type: "dir",  src: "Claude/templates/claudeos",               dest: ".claude/claudeos",      label: ".claude/claudeos (本体ツリー)" },
  { type: "dir",  src: "Claude/templates/claudeos/agents",        dest: ".claude/agents",        label: ".claude/agents (auto-discovery)" },
  { type: "dir",  src: "Claude/templates/claudeos/commands",      dest: ".claude/commands",      label: ".claude/commands" },
  { type: "dir",  src: "Claude/templates/claudeos/skills",        dest: ".claude/skills",        label: ".claude/skills" },
  { type: "dir",  src: "Claude/templates/claudeos/hooks",         dest: ".claude/hooks",         label: ".claude/hooks" },
  { type: "dir",  src: "Claude/templates/claude/workflows",       dest: ".claude/workflows",     label: ".claude/workflows (dynamic workflows)" },
  { type: "dir",  src: "Claude/templates/claudeos/scripts/tools", dest: "scripts/tools",         label: "scripts/tools" },
  { type: "file", src: "Claude/templates/claude/CLAUDE.md",       dest: "CLAUDE.md",             label: "CLAUDE.md" },
  { type: "file", src: "scripts/templates/claude-mcp.json",       dest: ".mcp.json",             label: ".mcp.json" },
  { type: "file", src: "scripts/templates/claude-statusline.py",  dest: ".claude/statusline.py", label: ".claude/statusline.py" },
];

// settings.json は copy-if-missing ではなく deep-merge で処理する (MAPPINGS とは別)。
// 既存プロジェクトの settings.json は permissions/env をカスタムしている場合があり、
// それらを保護しつつ ClaudeOS の hooks 登録 + 必要 env を *不足分だけ* 補完する。
const SETTINGS_TEMPLATE = "Claude/templates/claude/settings.json";
const STATE_TEMPLATE    = "Claude/templates/claude/claudeos/templates/state.json";
const SKILLS_DIRTY       = ".claude/claudeos/.skills-dirty";

// ──────────────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const args = { mode: null, target: null, projectFilter: null, configPath: null, all: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if      (a === "--dry-run")  args.mode = "dry-run";
    else if (a === "--apply")    args.mode = "apply";
    else if (a === "--all")      args.all = true;
    else if (a === "--target")   args.target = argv[++i];
    else if (a === "--project")  args.projectFilter = argv[++i];
    else if (a === "--config")   args.configPath = argv[++i];
    else if (a === "-h" || a === "--help") { printHelp(); process.exit(0); }
  }
  if (!args.mode) {
    console.error("ERROR: must specify --dry-run or --apply");
    printHelp();
    process.exit(2);
  }
  if (!args.all && !args.target && !args.projectFilter) {
    console.error("ERROR: must specify --target <path>, --project <name>, or --all");
    printHelp();
    process.exit(2);
  }
  return args;
}

function printHelp() {
  console.log(`
init-claudeos-project.js — install ClaudeOS into a project that does not have it yet.

Usage:
  node scripts/setup/init-claudeos-project.js --target <path> --dry-run
  node scripts/setup/init-claudeos-project.js --project <name> --apply
  node scripts/setup/init-claudeos-project.js --all --dry-run        # 全プロジェクト監査 (read-only)
  node scripts/setup/init-claudeos-project.js --all --apply          # 全プロジェクト一括導入/補完

Options:
  --target <path>   Absolute/relative path to the target project directory
  --project <name>  Resolve target via config/linux-projects.json or config/config.json
  --all             config の base 直下の全ディレクトリを対象 (.claude 非依存・監査/一括導入)
  --config <path>   Explicit config path (default: auto-detect)

Semantics: copy-if-missing (never overwrites existing files), idempotent.
After init, run migrate-agent-teams.js --apply to refresh session-start.js etc.

SSH tip (Linux): prefix with 'stdbuf -oL -eL' so output streams instead of appearing to hang.
`);
}

// .claude を要求しないターゲット解決 (init 対象はまさに .claude が無い)
function resolveTargetPath(args) {
  if (args.target) return path.resolve(args.target);

  const candidates = args.configPath ? [args.configPath] : [
    path.join(process.cwd(), "config", "config.json"),
    path.join(process.cwd(), "config", "linux-projects.json"),
  ];
  let cfgPath = null;
  for (const c of candidates) { if (fs.existsSync(c)) { cfgPath = c; break; } }
  if (!cfgPath) { console.error(`ERROR: no config found. Tried: ${candidates.join(", ")}`); process.exit(3); }

  let cfg;
  try { cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8")); }
  catch (e) { console.error(`ERROR: failed to parse ${cfgPath}: ${e.message}`); process.exit(3); }

  const base = cfg.basePath || cfg.projectsDir;
  if (!base) { console.error(`ERROR: ${cfgPath} has neither basePath nor projectsDir`); process.exit(3); }
  console.log(`[resolve] config: ${cfgPath}`);
  return path.join(base, args.projectFilter);
}

// --all 用: config の base (basePath/projectsDir) 直下の全ディレクトリを列挙 (.claude 非依存)
function listAllProjectDirs(configPath) {
  const candidates = configPath ? [configPath] : [
    path.join(process.cwd(), "config", "config.json"),
    path.join(process.cwd(), "config", "linux-projects.json"),
  ];
  let cfgPath = null;
  for (const c of candidates) { if (fs.existsSync(c)) { cfgPath = c; break; } }
  if (!cfgPath) { console.error(`ERROR: no config found. Tried: ${candidates.join(", ")}`); process.exit(3); }
  let cfg;
  try { cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8")); }
  catch (e) { console.error(`ERROR: failed to parse ${cfgPath}: ${e.message}`); process.exit(3); }
  const base = cfg.basePath || cfg.projectsDir;
  if (!base) { console.error(`ERROR: ${cfgPath} has neither basePath nor projectsDir`); process.exit(3); }
  console.log(`[resolve] config: ${cfgPath}  base: ${base}`);
  let entries = [];
  try { entries = fs.readdirSync(base, { withFileTypes: true }); }
  catch (e) { console.error(`ERROR: cannot read base dir ${base}: ${e.message}`); process.exit(3); }
  return entries.filter(e => e.isDirectory()).map(e => path.join(base, e.name));
}

// ──────────────────────────────────────────────────────────────────────
function copyDirIfMissing(srcDir, destDir, plan, dryRun) {
  if (!fs.existsSync(srcDir)) { plan.srcMissing.push(srcDir); return; }
  for (const e of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const s = path.join(srcDir, e.name);
    const d = path.join(destDir, e.name);
    if (e.isDirectory()) {
      copyDirIfMissing(s, d, plan, dryRun);
    } else if (e.isFile()) {
      if (fs.existsSync(d)) { plan.skip++; continue; }
      plan.create++;
      if (!dryRun) {
        fs.mkdirSync(path.dirname(d), { recursive: true });
        fs.copyFileSync(s, d);
      }
    }
  }
}

function copyFileIfMissing(src, dest, plan, dryRun, transform) {
  if (!fs.existsSync(src)) { plan.srcMissing.push(src); return; }
  if (fs.existsSync(dest)) { plan.skip++; return; }
  plan.create++;
  if (!dryRun) {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    if (transform) {
      fs.writeFileSync(dest, transform(fs.readFileSync(src, "utf8")), "utf8");
    } else {
      fs.copyFileSync(src, dest);
    }
  }
}

// settings.json を deep-merge: hooks (per-event, matcher+command で重複排除) と env を
// 不足分だけ追加。permissions と既存スカラー値は保護 (上書きしない)。
function mergeSettings(srcPath, destPath, plan, dryRun) {
  if (!fs.existsSync(srcPath)) { plan.srcMissing.push(srcPath); return; }
  if (!fs.existsSync(destPath)) {            // 新規: テンプレをそのままコピー
    plan.create++;
    if (!dryRun) { fs.mkdirSync(path.dirname(destPath), { recursive: true }); fs.copyFileSync(srcPath, destPath); }
    return;
  }
  let tmpl, cur;
  try { tmpl = JSON.parse(fs.readFileSync(srcPath, "utf8")); cur = JSON.parse(fs.readFileSync(destPath, "utf8")); }
  catch (e) { console.error(`  WARN: settings.json parse 失敗、merge skip: ${e.message}`); plan.skip++; return; }

  let added = 0;
  // top-level キー (hooks/env/permissions 以外): 欠けていれば追加、既存は保護
  for (const k of Object.keys(tmpl)) {
    if (k === "hooks" || k === "env" || k === "permissions") continue;
    if (!(k in cur)) { cur[k] = tmpl[k]; added++; }
  }
  // env: 欠けている key を追加、既存値は保護
  if (tmpl.env && typeof tmpl.env === "object") {
    cur.env = (cur.env && typeof cur.env === "object") ? cur.env : {};
    for (const [k, v] of Object.entries(tmpl.env)) {
      if (!(k in cur.env)) { cur.env[k] = v; added++; }
    }
  }
  // hooks: event ごとに (matcher + command 群) シグネチャで重複排除して不足分を追加
  const sig = (e) => JSON.stringify({ m: e.matcher, c: (e.hooks || []).map(h => h.command) });
  if (tmpl.hooks && typeof tmpl.hooks === "object") {
    cur.hooks = (cur.hooks && typeof cur.hooks === "object") ? cur.hooks : {};
    for (const [event, entries] of Object.entries(tmpl.hooks)) {
      cur.hooks[event] = Array.isArray(cur.hooks[event]) ? cur.hooks[event] : [];
      const have = new Set(cur.hooks[event].map(sig));
      for (const entry of entries) {
        if (!have.has(sig(entry))) { cur.hooks[event].push(entry); have.add(sig(entry)); added++; }
      }
    }
  }
  // permissions は各プロジェクトのセキュリティ方針なので一切触らない。

  if (added > 0) {
    plan.merge += added;
    if (!dryRun) {
      fs.copyFileSync(destPath, destPath + ".bak-init");
      const tmp = destPath + ".tmp." + process.pid;
      fs.writeFileSync(tmp, JSON.stringify(cur, null, 2) + "\n", "utf8");
      fs.renameSync(tmp, destPath);
    }
  } else {
    plan.skip++;
  }
}

// ──────────────────────────────────────────────────────────────────────
// 1 プロジェクトを処理し totals を返す。quiet=true でマッピング毎の行出力を抑制 (--all 監査用)。
function processProject(targetPath, dryRun, quiet) {
  const projName = path.basename(targetPath);
  const tag      = dryRun ? "[DRY-RUN]" : "[APPLY]";
  const log      = quiet ? () => {} : (m) => console.log(m);
  const totals   = { create: 0, skip: 0, merge: 0, srcMissing: [] };

  for (const m of MAPPINGS) {
    const src  = path.join(REPO_ROOT, m.src);
    const dest = path.join(targetPath, m.dest);
    const plan = { create: 0, skip: 0, srcMissing: [] };
    if (m.type === "dir") copyDirIfMissing(src, dest, plan, dryRun);
    else                  copyFileIfMissing(src, dest, plan, dryRun);
    totals.create += plan.create;
    totals.skip   += plan.skip;
    totals.srcMissing.push(...plan.srcMissing);
    log(`  ${tag} ${m.label}: +${plan.create} new / ${plan.skip} kept${plan.srcMissing.length ? " (SOURCE MISSING!)" : ""}`);
  }

  // settings.json を deep-merge (permissions/env 保護しつつ ClaudeOS の hooks 登録 + env を補完)
  {
    const src  = path.join(REPO_ROOT, SETTINGS_TEMPLATE);
    const dest = path.join(targetPath, ".claude/settings.json");
    const plan = { create: 0, skip: 0, merge: 0, srcMissing: [] };
    mergeSettings(src, dest, plan, dryRun);
    totals.create += plan.create; totals.skip += plan.skip; totals.merge += plan.merge; totals.srcMissing.push(...plan.srcMissing);
    const detail = plan.create ? "+1 new" : (plan.merge ? `+${plan.merge} merged (hooks/env)` : "up-to-date (kept)");
    log(`  ${tag} .claude/settings.json: ${detail}${plan.srcMissing.length ? " (SOURCE MISSING!)" : ""}`);
  }

  // state.json を seed (YOUR_PROJECT → 実プロジェクト名に置換)
  {
    const src  = path.join(REPO_ROOT, STATE_TEMPLATE);
    const dest = path.join(targetPath, "state.json");
    const plan = { create: 0, skip: 0, srcMissing: [] };
    copyFileIfMissing(src, dest, plan, dryRun, (txt) => txt.replace(/"YOUR_PROJECT"/g, JSON.stringify(projName)));
    totals.create += plan.create; totals.skip += plan.skip; totals.srcMissing.push(...plan.srcMissing);
    log(`  ${tag} state.json (name=${projName}): +${plan.create} new / ${plan.skip} kept${plan.srcMissing.length ? " (SOURCE MISSING!)" : ""}`);
  }

  // skills 配置後に .skills-dirty を touch → 次セッションで reloadSkills 発火
  if (!dryRun && totals.create > 0) {
    try {
      const sentinel = path.join(targetPath, SKILLS_DIRTY);
      fs.mkdirSync(path.dirname(sentinel), { recursive: true });
      fs.writeFileSync(sentinel, new Date().toISOString() + "\n", "utf8");
      log(`  [APPLY] touched ${SKILLS_DIRTY} (次セッションで skill 再スキャン)`);
    } catch (e) { console.error(`  WARN: failed to touch sentinel: ${e.message}`); }
  }

  return totals;
}

// --all 監査の分類ラベル
function classify(t) {
  if (t.srcMissing.length)                  return "SRC-MISSING";
  if (t.create === 0 && t.merge === 0)      return "OK (complete)";
  if (t.create >= 100)                      return `UN-ONBOARDED (create=${t.create})`;
  if (t.create > 0)                         return `PARTIAL (create=${t.create} merge=${t.merge})`;
  return `SETTINGS-GAP (merge=${t.merge})`;
}

// ──────────────────────────────────────────────────────────────────────
function main() {
  const args   = parseArgs(process.argv.slice(2));
  const dryRun = args.mode === "dry-run";

  // --all: config の base 直下を全走査 (.claude 非依存)。dry-run=監査 / apply=一括導入。
  if (args.all) {
    const dirs     = listAllProjectDirs(args.configPath);
    const selfName = path.basename(process.cwd());
    console.log(`[init --all] mode: ${args.mode}  dirs: ${dirs.length} (self "${selfName}" excluded)`);
    if (!dryRun) console.log(`[init --all] --apply は既存 ClaudeOS プロジェクト (.claude/claudeos あり) のみ対象。未導入 dir は skip。`);
    console.log("");
    const agg = {};
    for (const d of dirs) {
      const n = path.basename(d);
      if (n === selfName) continue;
      const onboarded = fs.existsSync(path.join(d, ".claude", "claudeos"));
      // --apply ガード: .claude/claudeos が無い dir (.pytest_cache / アーカイブ等) は
      // onboard せず skip し litter を防ぐ。新規 onboard は --project <name> --apply を明示使用。
      if (!dryRun && !onboarded) {
        agg["SKIP-NEW"] = (agg["SKIP-NEW"] || 0) + 1;
        console.log(`  ${n.padEnd(48)} SKIP-NEW (no .claude/claudeos — onboard: --project ${n} --apply)`);
        continue;
      }
      const t   = processProject(d, dryRun, true);   // quiet
      const cls = classify(t);
      const key = cls.split(" ")[0];
      agg[key]  = (agg[key] || 0) + 1;
      console.log(`  ${n.padEnd(48)} ${cls}`);
    }
    console.log("");
    console.log("─".repeat(72));
    console.log(`Summary (${dryRun ? "audit" : "applied"}): ${Object.entries(agg).map(([k, v]) => `${k}=${v}`).join("  ")}`);
    if (dryRun) console.log("適用: --all --apply は既存 ClaudeOS projects のみ完成 (未導入 dir は skip / 既存保護 / backup / 冪等)。");
    return;
  }

  // 単一プロジェクト (verbose)
  const targetPath = resolveTargetPath(args);
  const projName   = path.basename(targetPath);
  if (!fs.existsSync(targetPath)) {
    console.error(`ERROR: target project directory not found: ${targetPath}`);
    process.exit(4);
  }
  console.log(`[init] target : ${targetPath}`);
  console.log(`[init] project: ${projName}`);
  console.log(`[init] mode   : ${args.mode}`);
  console.log("");

  const totals = processProject(targetPath, dryRun, false);

  console.log("");
  console.log("─".repeat(60));
  console.log(`Summary: ${dryRun ? "would-create" : "created"}=${totals.create}  ${dryRun ? "would-merge" : "merged"}=${totals.merge}  kept=${totals.skip}`);
  if (totals.srcMissing.length) {
    console.log(`⚠️  source missing (${totals.srcMissing.length}): ${totals.srcMissing.join(", ")}`);
  }
  if (totals.create === 0 && totals.merge === 0) {
    console.log("ClaudeOS は既に導入済みのようです (変更なし)。");
  } else if (!dryRun) {
    console.log("");
    console.log("次の推奨ステップ: session-start.js 等を最新化");
    console.log("  node scripts/setup/migrate-agent-teams.js --project " + projName + " --apply");
  }
}

main();
