#!/usr/bin/env node
// add-skill-frontmatter.js — ClaudeOS skills に YAML frontmatter (name/description) を付与
//
// 背景: Claude Code の skill discovery は `---\nname:\ndescription:\n---` frontmatter 必須
//       (description が起動トリガー)。ClaudeOS の 66 skill は frontmatter 無しの
//       Markdown のみで、auto-trigger していなかった。本スクリプトで一括付与し有効化する。
//       出典: "Lessons from Building Claude Code: How We Use Skills" (Anthropic, 2026-03)
//
// description は各 SKILL.md の「## 概要」(「この skill は <X> ための実務向けガイドです。」) から
// <X>(= 起動トリガー語) を抽出し、利用場面を添えて決定論的に合成する。
//
// 使い方:
//   node scripts/setup/add-skill-frontmatter.js --dry-run               # SOT をプレビュー
//   node scripts/setup/add-skill-frontmatter.js --apply                 # SOT に付与
//   node scripts/setup/add-skill-frontmatter.js --apply --dir <path>    # 対象 skills ディレクトリ上書き
//   既存 frontmatter (--- 開始) は skip (冪等)。

"use strict";
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const APPLY = args.includes("--apply");
const dirIdx = args.indexOf("--dir");
const SKILLS_DIR = dirIdx !== -1
  ? path.resolve(args[dirIdx + 1])
  : path.resolve(__dirname, "../../Claude/templates/claudeos/skills");

if (!DRY_RUN && !APPLY) {
  console.log("Usage: node add-skill-frontmatter.js --dry-run | --apply [--dir <skills-dir>]");
  process.exit(0);
}
if (!fs.existsSync(SKILLS_DIR)) {
  console.error(`skills dir not found: ${SKILLS_DIR}`);
  process.exit(1);
}

// 概要から description を合成する
function buildDescription(content) {
  // 「## 概要」直後の本文ブロックを取得
  const m = content.match(/##\s*概要\s*\r?\n+([^\r\n]+)/);
  let overview = m ? m[1].trim() : "";
  // 「この skill は <X> ための実務向けガイドです。」から <X> を抽出
  const core = overview.match(/^この\s*skill\s*は\s*(.+?)\s*ための実務向けガイドです。?$/);
  let purpose = core ? core[1].trim() : overview.replace(/。$/, "");
  if (!purpose) purpose = "ClaudeOS 運用の実務";
  // description は起動トリガー。purpose(= 具体的なトリガー語)を高シグナルで載せる。
  // 全 skill 共通の定型「when」句は差別化に寄与せず「当たり前」なので付けない。
  let desc = `${purpose}ための実務ガイド。`;
  if (desc.length > 240) desc = desc.slice(0, 237) + "...";
  return desc;
}

// YAML 用に description を二重引用符でクオートしエスケープ
function yamlQuote(s) {
  return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

const skillDirs = fs.readdirSync(SKILLS_DIR, { withFileTypes: true })
  .filter(e => e.isDirectory())
  .map(e => e.name)
  .sort();

let added = 0, skipped = 0, errors = 0;
console.log(`\n🔧 add-skill-frontmatter.js — ${DRY_RUN ? "DRY-RUN" : "APPLY"} / dir=${SKILLS_DIR}`);
console.log(`📁 skill 数: ${skillDirs.length}\n`);

for (const name of skillDirs) {
  const file = path.join(SKILLS_DIR, name, "SKILL.md");
  if (!fs.existsSync(file)) { console.log(`  ⬛ ${name}: SKILL.md なし`); skipped++; continue; }
  try {
    const raw = fs.readFileSync(file, "utf8");
    if (/^﻿?---\r?\n/.test(raw)) { console.log(`  ⬛ ${name}: frontmatter 既存`); skipped++; continue; }

    const eol = raw.includes("\r\n") ? "\r\n" : "\n";
    const description = buildDescription(raw);
    const fm = [
      "---",
      `name: ${name}`,
      `description: ${yamlQuote(description)}`,
      "---",
      "",
      "",
    ].join(eol);
    const out = fm + raw;

    if (DRY_RUN) {
      console.log(`  ✅ ${name}`);
      console.log(`       description: ${description}`);
    } else if (APPLY) {
      fs.writeFileSync(file, out, "utf8");
      console.log(`  ✅ ${name}: frontmatter 付与`);
    }
    added++;
  } catch (e) {
    console.log(`  ❌ ${name}: ${e.message}`);
    errors++;
  }
}

console.log(`\n── サマリー ──────────────`);
console.log(`📊 付与: ${added} / skip: ${skipped} / エラー: ${errors}`);
if (DRY_RUN) console.log(`⚠️ DRY-RUN。--apply で書き込み。`);
