#!/usr/bin/env node
// migrate-v2159.js — Claude Code v2.1.159 新機能を全登録プロジェクトへ配布
//
// 変更内容:
//   1. settings.json に worktree.baseRef: "head" を追加
//   2. PreToolUse/Bash フックに continueOnBlock: true を追加
//   3. PostToolUse/Edit|Write|MultiEdit フックに continueOnBlock: true を追加
//   4. CLAUDE.md の "Experimental" 表記を削除・バージョン更新
//
// 使い方:
//   node scripts/setup/migrate-v2159.js --dry-run     # プレビュー
//   node scripts/setup/migrate-v2159.js --apply        # 全プロジェクト適用
//   node scripts/setup/migrate-v2159.js --rollback     # バックアップから復元

"use strict";

const fs   = require("fs");
const path = require("path");

const BACKUP_SUFFIX = ".bak-v2159";
const PROJECTS_BASE = path.resolve(__dirname, "..", "..", "..");

const args = process.argv.slice(2);
const DRY_RUN   = args.includes("--dry-run");
const APPLY     = args.includes("--apply");
const ROLLBACK  = args.includes("--rollback");
const VERBOSE   = args.includes("--verbose");
const projectFilter = (() => {
  const idx = args.indexOf("--project");
  return idx !== -1 ? args[idx + 1] : null;
})();

if (!DRY_RUN && !APPLY && !ROLLBACK) {
  console.log("Usage: node migrate-v2159.js --dry-run | --apply | --rollback [--project <name>] [--verbose]");
  process.exit(0);
}

// ── プロジェクト一覧 ──────────────────────────────────────────────────────────

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

console.log(`\n🔧 migrate-v2159.js — Claude Code v2.1.159 マイグレーション`);
console.log(`📁 対象プロジェクト数: ${projects.length}${projectFilter ? ` (filter: ${projectFilter})` : ""}`);
if (DRY_RUN)  console.log("🔍 DRY-RUN モード（変更なし）");
if (APPLY)    console.log("⚡ APPLY モード（変更を実行）");
if (ROLLBACK) console.log("↩️  ROLLBACK モード（バックアップから復元）");
console.log("");

// ── settings.json マイグレーション ───────────────────────────────────────────

function migrateSettings(projectPath) {
  const settingsPath = path.join(projectPath, ".claude", "settings.json");
  if (!fs.existsSync(settingsPath)) return { changed: false, reason: "settings.json not found" };

  const raw = fs.readFileSync(settingsPath, "utf8");
  let settings;
  try { settings = JSON.parse(raw); } catch (e) { return { changed: false, reason: "JSON parse error" }; }

  let changed = false;
  const original = JSON.stringify(settings, null, 2);

  // 1. worktree.baseRef
  if (!settings.worktree || !settings.worktree.baseRef) {
    settings.worktree = Object.assign({}, settings.worktree || {}, { baseRef: "head" });
    changed = true;
    if (VERBOSE) console.log(`  + worktree.baseRef: "head"`);
  }

  // 2. PreToolUse/Bash — continueOnBlock
  const preToolUse = (settings.hooks || {}).PreToolUse || [];
  for (const group of preToolUse) {
    if (group.matcher && group.matcher.includes("Bash")) {
      for (const h of group.hooks || []) {
        if (!h.continueOnBlock) {
          h.continueOnBlock = true;
          changed = true;
          if (VERBOSE) console.log(`  + PreToolUse/Bash continueOnBlock: true`);
        }
      }
    }
  }

  // 3. PostToolUse/Edit|Write|MultiEdit — continueOnBlock
  const postToolUse = (settings.hooks || {}).PostToolUse || [];
  for (const group of postToolUse) {
    if (group.matcher && /Edit|Write|MultiEdit/.test(group.matcher)) {
      for (const h of group.hooks || []) {
        if (!h.continueOnBlock) {
          h.continueOnBlock = true;
          changed = true;
          if (VERBOSE) console.log(`  + PostToolUse/Edit|Write|MultiEdit continueOnBlock: true`);
        }
      }
    }
  }

  if (!changed) return { changed: false, reason: "already up-to-date" };

  const newContent = JSON.stringify(settings, null, 2) + "\n";
  if (APPLY) {
    fs.writeFileSync(settingsPath + BACKUP_SUFFIX, raw, "utf8");
    fs.writeFileSync(settingsPath, newContent, "utf8");
  }
  return { changed: true, original, newContent };
}

// ── CLAUDE.md マイグレーション ─────────────────────────────────────────────────

function migrateClaude(projectPath) {
  const claudePath = path.join(projectPath, ".claude", "CLAUDE.md");
  if (!fs.existsSync(claudePath)) return { changed: false, reason: "CLAUDE.md not found" };

  let content = fs.readFileSync(claudePath, "utf8");
  const original = content;
  let changed = false;

  // Experimental 表記削除
  if (content.includes("（Experimental）")) {
    content = content.replace(/（Experimental）/g, "（**公式機能** v2.1.159+）");
    changed = true;
  }
  // 旧バージョン表記更新
  if (content.includes("v2.1.139+")) {
    content = content.replace(/v2\.1\.139\+/g, "v2.1.159+");
    changed = true;
  }

  if (!changed) return { changed: false, reason: "already up-to-date" };

  if (APPLY) {
    fs.writeFileSync(claudePath + BACKUP_SUFFIX, original, "utf8");
    fs.writeFileSync(claudePath, content, "utf8");
  }
  return { changed: true };
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

  // settings.json
  try {
    const sr = migrateSettings(projectPath);
    if (sr.changed) { console.log(`  ✅ settings.json 更新`); totalChanged++; }
    else            { console.log(`  ⬛ settings.json: ${sr.reason}`); totalSkipped++; }
  } catch (e) {
    console.log(`  ❌ settings.json エラー: ${e.message}`); totalErrors++;
  }

  // CLAUDE.md
  try {
    const cr = migrateClaude(projectPath);
    if (cr.changed) { console.log(`  ✅ CLAUDE.md 更新`); }
    else            { console.log(`  ⬛ CLAUDE.md: ${cr.reason}`); }
  } catch (e) {
    console.log(`  ❌ CLAUDE.md エラー: ${e.message}`); totalErrors++;
  }
}

console.log(`\n── サマリー ────────────────────────────────────`);
console.log(`📊 変更あり: ${totalChanged} / スキップ: ${totalSkipped} / エラー: ${totalErrors}`);
if (DRY_RUN) console.log(`⚠️  DRY-RUN のため実際の変更は行われていません。--apply で適用してください。`);
if (APPLY)   console.log(`✅ 変更を適用しました。バックアップは *.bak-v2159 に保存されています。`);
console.log(`──────────────────────────────────────────────\n`);
