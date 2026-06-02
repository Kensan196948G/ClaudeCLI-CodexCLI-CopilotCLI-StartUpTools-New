#!/usr/bin/env node
// migrate-workflows-agentteams.js — Workflows / Agent Teams 公式ドキュメント対応
//
// 変更内容:
//   1. CLAUDE.md の「公式機能」誤記を修正 → 正しい「Experimental」表記に戻す
//   2. settings.json に TeammateIdle / TaskCreated / TaskCompleted フックを追加
//   3. .claude/workflows/ ディレクトリを作成（プロジェクトワークフロー保存場所）
//   4. フックスクリプトを各プロジェクトにコピー（3ファイル）
//
// 根拠:
//   https://code.claude.com/docs/en/agent-teams — Agent Teams は experimental のまま
//   https://code.claude.com/docs/en/workflows   — TeammateIdle/TaskCreated/TaskCompleted が新規追加
//
// 使い方:
//   node scripts/setup/migrate-workflows-agentteams.js --dry-run     # プレビュー
//   node scripts/setup/migrate-workflows-agentteams.js --apply        # 全プロジェクト適用
//   node scripts/setup/migrate-workflows-agentteams.js --rollback     # 復元

"use strict";

const fs   = require("fs");
const path = require("path");

const BACKUP_SUFFIX  = ".bak-workflows-agentteams";
const PROJECTS_BASE  = path.resolve(__dirname, "../../..");
const TEMPLATE_HOOKS = path.resolve(__dirname, "../../Claude/templates/claudeos/scripts/hooks");

const args = process.argv.slice(2);
const DRY_RUN  = args.includes("--dry-run");
const APPLY    = args.includes("--apply");
const ROLLBACK = args.includes("--rollback");
const VERBOSE  = args.includes("--verbose");
const projectFilter = (() => {
  const idx = args.indexOf("--project");
  return idx !== -1 ? args[idx + 1] : null;
})();

if (!DRY_RUN && !APPLY && !ROLLBACK) {
  console.log("Usage: node migrate-workflows-agentteams.js --dry-run | --apply | --rollback [--project <name>] [--verbose]");
  process.exit(0);
}

function listRegisteredProjects() {
  return fs.readdirSync(PROJECTS_BASE, { withFileTypes: true })
    .filter(e => e.isDirectory() && e.name !== "ClaudeCode-StartUpTools-New")
    .map(e => path.join(PROJECTS_BASE, e.name))
    .filter(p => fs.existsSync(path.join(p, ".claude", "settings.json")));
}

const projects = listRegisteredProjects().filter(p => {
  if (!projectFilter) return true;
  return path.basename(p) === projectFilter;
});

console.log(`\n🔧 migrate-workflows-agentteams.js — Workflows / Agent Teams 対応`);
console.log(`📁 対象プロジェクト数: ${projects.length}${projectFilter ? ` (filter: ${projectFilter})` : ""}`);
if (DRY_RUN)  console.log("🔍 DRY-RUN モード（変更なし）");
if (APPLY)    console.log("⚡ APPLY モード（変更を実行）");
if (ROLLBACK) console.log("↩️  ROLLBACK モード（バックアップから復元）");
console.log("");

// ── 1. CLAUDE.md の「公式機能」誤記修正 ───────────────────────────────────────

function fixClaude(projectPath) {
  const claudePath = path.join(projectPath, ".claude", "CLAUDE.md");
  if (!fs.existsSync(claudePath)) return { changed: false, reason: "not found" };

  let content = fs.readFileSync(claudePath, "utf8");
  const original = content;
  let changed = false;

  // 前回マイグレーションの誤記を修正
  if (content.includes("**公式機能** v2.1.159+")) {
    content = content.replace(
      /Agent Teams による並列協調開発（\*\*公式機能\*\* v2\.1\.159\+）/g,
      "Agent Teams による並列協調開発（**Experimental**・`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 必須）"
    );
    changed = true;
  }
  // 旧 Experimental のみ表記を詳細表記に更新
  if (content.includes("（Experimental）")) {
    content = content.replace(
      /Agent Teams による並列協調開発（Experimental）/g,
      "Agent Teams による並列協調開発（**Experimental**・`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 必須）"
    );
    changed = true;
  }

  if (!changed) return { changed: false, reason: "already up-to-date" };

  if (APPLY) {
    fs.writeFileSync(claudePath + BACKUP_SUFFIX, original, "utf8");
    fs.writeFileSync(claudePath, content, "utf8");
  }
  return { changed: true };
}

// ── 2. settings.json に新フック追加 ───────────────────────────────────────────

const NEW_HOOKS = {
  TeammateIdle: [{ matcher: "*", hooks: [{ type: "command", command: "node .claude/claudeos/scripts/hooks/teammate-idle-gate.js" }] }],
  TaskCreated:  [{ matcher: "*", hooks: [{ type: "command", command: "node .claude/claudeos/scripts/hooks/task-created-gate.js" }] }],
  TaskCompleted:[{ matcher: "*", hooks: [{ type: "command", command: "node .claude/claudeos/scripts/hooks/task-completed-gate.js" }] }],
};

function fixSettings(projectPath) {
  const settingsPath = path.join(projectPath, ".claude", "settings.json");
  if (!fs.existsSync(settingsPath)) return { changed: false, reason: "not found" };

  const raw = fs.readFileSync(settingsPath, "utf8");
  let settings;
  try { settings = JSON.parse(raw); } catch (e) { return { changed: false, reason: "JSON parse error" }; }

  if (!settings.hooks) settings.hooks = {};
  let changed = false;

  for (const [hookName, hookConfig] of Object.entries(NEW_HOOKS)) {
    if (!settings.hooks[hookName]) {
      settings.hooks[hookName] = hookConfig;
      changed = true;
      if (VERBOSE) console.log(`  + hooks.${hookName}`);
    }
  }

  if (!changed) return { changed: false, reason: "hooks already present" };

  const newContent = JSON.stringify(settings, null, 2) + "\n";
  if (APPLY) {
    fs.writeFileSync(settingsPath + BACKUP_SUFFIX, raw, "utf8");
    fs.writeFileSync(settingsPath, newContent, "utf8");
  }
  return { changed: true };
}

// ── 3. .claude/workflows/ ディレクトリ作成 ────────────────────────────────────

function ensureWorkflowsDir(projectPath) {
  const wfDir = path.join(projectPath, ".claude", "workflows");
  if (fs.existsSync(wfDir)) return { changed: false, reason: "already exists" };
  if (APPLY) fs.mkdirSync(wfDir, { recursive: true });
  return { changed: true };
}

// ── 4. フックスクリプトコピー ─────────────────────────────────────────────────

const HOOK_FILES = ["teammate-idle-gate.js", "task-created-gate.js", "task-completed-gate.js"];

function copyHookScripts(projectPath) {
  const targetHooksDir = path.join(projectPath, ".claude", "claudeos", "scripts", "hooks");
  if (!fs.existsSync(targetHooksDir)) return { changed: false, reason: "hooks dir not found" };

  let copied = 0;
  for (const fname of HOOK_FILES) {
    const src  = path.join(TEMPLATE_HOOKS, fname);
    const dest = path.join(targetHooksDir, fname);
    if (!fs.existsSync(src)) { if (VERBOSE) console.log(`  ⚠️  source not found: ${fname}`); continue; }
    if (fs.existsSync(dest)) {
      // Update if content differs
      const srcContent  = fs.readFileSync(src, "utf8");
      const destContent = fs.readFileSync(dest, "utf8");
      if (srcContent === destContent) continue;
    }
    if (APPLY) fs.copyFileSync(src, dest);
    copied++;
    if (VERBOSE) console.log(`  + hook: ${fname}`);
  }
  return { changed: copied > 0, count: copied };
}

// ── ロールバック ──────────────────────────────────────────────────────────────

function rollback(projectPath) {
  const files = [
    path.join(projectPath, ".claude", "settings.json"),
    path.join(projectPath, ".claude", "CLAUDE.md"),
  ];
  let restored = 0;
  for (const f of files) {
    const bak = f + BACKUP_SUFFIX;
    if (fs.existsSync(bak)) {
      fs.copyFileSync(bak, f);
      fs.unlinkSync(bak);
      restored++;
      if (VERBOSE) console.log(`  ↩️  restored: ${path.basename(f)}`);
    }
  }
  return restored;
}

// ── メイン実行 ────────────────────────────────────────────────────────────────

let totalChanged = 0;
let totalSkipped = 0;
let totalErrors  = 0;

for (const projectPath of projects) {
  const name = path.basename(projectPath);
  console.log(`📂 ${name}`);

  if (ROLLBACK) {
    const count = rollback(projectPath);
    if (count > 0) { console.log(`  ✅ ${count} ファイル復元`); totalChanged++; }
    else           { console.log(`  ⚠️  バックアップなし`); totalSkipped++; }
    continue;
  }

  // CLAUDE.md 修正
  try {
    const r = fixClaude(projectPath);
    if (r.changed) { console.log(`  ✅ CLAUDE.md 誤記修正`); totalChanged++; }
    else           { console.log(`  ⬛ CLAUDE.md: ${r.reason}`); totalSkipped++; }
  } catch (e) { console.log(`  ❌ CLAUDE.md: ${e.message}`); totalErrors++; }

  // settings.json hooks 追加
  try {
    const r = fixSettings(projectPath);
    if (r.changed) { console.log(`  ✅ settings.json hooks 追加`); }
    else           { console.log(`  ⬛ settings.json: ${r.reason}`); }
  } catch (e) { console.log(`  ❌ settings.json: ${e.message}`); totalErrors++; }

  // .claude/workflows/ ディレクトリ
  try {
    const r = ensureWorkflowsDir(projectPath);
    if (r.changed) { console.log(`  ✅ .claude/workflows/ 作成`); }
    else           { console.log(`  ⬛ workflows/: ${r.reason}`); }
  } catch (e) { console.log(`  ❌ workflows/: ${e.message}`); totalErrors++; }

  // フックスクリプトコピー
  try {
    const r = copyHookScripts(projectPath);
    if (r.changed) { console.log(`  ✅ フックスクリプト ${r.count} 件コピー`); }
    else           { console.log(`  ⬛ hooks: up-to-date`); }
  } catch (e) { console.log(`  ❌ hooks copy: ${e.message}`); totalErrors++; }
}

console.log(`\n── サマリー ────────────────────────────────────`);
console.log(`📊 変更あり: ${totalChanged} / スキップ: ${totalSkipped} / エラー: ${totalErrors}`);
if (DRY_RUN) console.log(`⚠️  DRY-RUN のため実際の変更は行われていません。--apply で適用してください。`);
if (APPLY)   console.log(`✅ 適用完了。バックアップは *.bak-workflows-agentteams に保存されています。`);
console.log(`──────────────────────────────────────────────\n`);
