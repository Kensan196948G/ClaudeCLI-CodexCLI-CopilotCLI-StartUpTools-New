#!/usr/bin/env node
/**
 * add-skill-frontmatter.js
 *
 * 全 SKILL.md に `name` / `description` frontmatter を付与する保守スクリプト。
 *
 * 背景:
 *   Claude Code は SKILL.md frontmatter の `description` を読んで skill の
 *   自動発火 / 自動選択を判断する。frontmatter が無い skill は名前による
 *   明示呼び出ししか効かず「休眠状態」になる (Anthropic blog: Model-Focused
 *   Descriptions)。本スクリプトで配布元テンプレと local copy の両方を回復する。
 *
 * 抽出ロジック:
 *   - name        : skill フォルダ名
 *   - description : `## 概要` の scaffold 文 `この skill は <X> ための実務向け
 *                   ガイドです。` から X を抽出し `<X>ときに使う。` へ整形。
 *                   scaffold に一致しない手書き skill は EXCEPTIONS で補う。
 *
 * 冪等性:
 *   先頭が `---` の SKILL.md は frontmatter 既存と見なしてスキップする。
 *
 * 使い方:
 *   node scripts/setup/add-skill-frontmatter.js --dry-run   # 変更プレビュー
 *   node scripts/setup/add-skill-frontmatter.js             # 適用
 */

"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

// 配布元 (source-of-truth) と local runtime copy の両方を処理する。
const SKILL_DIRS = [
  path.join(REPO_ROOT, "Claude", "templates", "claudeos", "skills"),
  path.join(REPO_ROOT, ".claude", "claudeos", "skills"),
];

// scaffold に一致しない手書き skill の description (フォルダ名 -> description)。
const EXCEPTIONS = {
  "performance-review":
    "差分や既存コードを性能観点でレビューし、ホットスポット・計算量・I/O 回数・並列性・メモリ・DB クエリのリグレッションを検出するときに使う。",
  "requirements-extractor":
    "議事録・要件メモ・メール・Slack ログなどの非構造化テキストから実行可能タスクと受け入れ基準を抽出し Issue 化するときに使う。",
};

// `## 概要` 直後の scaffold 文から X を取り出す正規表現。
const SCAFFOLD_RE = /この skill は\s*(.+?)\s*ための実務向けガイドです。/;

const DRY_RUN = process.argv.includes("--dry-run");

/** YAML double-quoted scalar として安全な文字列にする。 */
function yamlQuote(value) {
  return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

/** SKILL.md 本文から description を決定する。決められなければ null。 */
function deriveDescription(folderName, body) {
  if (EXCEPTIONS[folderName]) return EXCEPTIONS[folderName];
  const m = body.match(SCAFFOLD_RE);
  if (m) {
    const x = m[1].trim();
    return `${x}ときに使う。`;
  }
  return null;
}

function processSkillFile(skillMdPath, folderName) {
  const original = fs.readFileSync(skillMdPath, "utf8");

  if (original.startsWith("---")) {
    return { status: "skip", reason: "frontmatter 既存" };
  }

  const description = deriveDescription(folderName, original);
  if (!description) {
    return { status: "error", reason: "description を抽出できず (scaffold 不一致 & 例外未定義)" };
  }

  const frontmatter =
    "---\n" +
    `name: ${folderName}\n` +
    `description: ${yamlQuote(description)}\n` +
    "---\n\n";

  if (DRY_RUN) {
    return { status: "would-write", description };
  }

  fs.writeFileSync(skillMdPath, frontmatter + original, "utf8");
  return { status: "written", description };
}

function main() {
  let totals = { written: 0, skip: 0, error: 0, wouldWrite: 0, missing: 0 };
  const errors = [];

  for (const dir of SKILL_DIRS) {
    if (!fs.existsSync(dir)) {
      console.log(`⚠️  ディレクトリ無し: ${path.relative(REPO_ROOT, dir)}`);
      continue;
    }
    console.log(`\n📁 ${path.relative(REPO_ROOT, dir)}`);

    const folders = fs
      .readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();

    for (const folderName of folders) {
      const skillMdPath = path.join(dir, folderName, "SKILL.md");
      if (!fs.existsSync(skillMdPath)) {
        totals.missing++;
        console.log(`   ❓ ${folderName}: SKILL.md 無し`);
        continue;
      }
      const result = processSkillFile(skillMdPath, folderName);
      switch (result.status) {
        case "written":
          totals.written++;
          console.log(`   ✅ ${folderName} → ${result.description}`);
          break;
        case "would-write":
          totals.wouldWrite++;
          console.log(`   📝 ${folderName} → ${result.description}`);
          break;
        case "skip":
          totals.skip++;
          console.log(`   ⏭️  ${folderName} (${result.reason})`);
          break;
        case "error":
          totals.error++;
          errors.push(`${folderName}: ${result.reason}`);
          console.log(`   ❌ ${folderName} (${result.reason})`);
          break;
      }
    }
  }

  console.log("\n📊 サマリ");
  if (DRY_RUN) {
    console.log(`   付与予定: ${totals.wouldWrite}`);
  } else {
    console.log(`   付与: ${totals.written}`);
  }
  console.log(`   スキップ(既存): ${totals.skip}`);
  console.log(`   SKILL.md 欠落: ${totals.missing}`);
  console.log(`   エラー: ${totals.error}`);

  if (errors.length > 0) {
    console.log("\n❌ エラー詳細:");
    errors.forEach((e) => console.log(`   - ${e}`));
    process.exit(1);
  }
}

main();
