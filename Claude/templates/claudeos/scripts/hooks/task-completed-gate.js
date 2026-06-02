#!/usr/bin/env node
// task-completed-gate.js — TaskCompleted hook
//
// Runs when a task is being marked as complete.
// Exit code 2 + message → task completion is blocked with feedback.
// Exit code 0 → task is marked complete normally.
//
// Hook input (stdin JSON):
//   { "task_title": "...", "task_description": "...", "completion_notes": "...", "session_id": "..." }

"use strict";

const fs   = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

async function main() {
  let input = {};
  try {
    const raw = fs.readFileSync("/dev/stdin", "utf8").trim();
    if (raw) input = JSON.parse(raw);
  } catch (_) {}

  const title   = (input.task_title || input.title || "").trim();
  const notes   = (input.completion_notes || input.notes || "").toLowerCase();

  // Tasks that modify source code require test evidence
  const codeKeywords = ["fix", "implement", "refactor", "add", "修正", "実装", "追加"];
  const isCodeTask = codeKeywords.some(k => title.toLowerCase().includes(k));

  if (!isCodeTask) {
    process.exit(0); // Non-code tasks (research, docs) pass through
  }

  // Check if completion notes mention test results
  const testEvidence = ["test", "pass", "spec", "テスト", "通過", "成功", "確認"];
  const hasTestEvidence = testEvidence.some(k => notes.includes(k));

  if (!hasTestEvidence) {
    // Try to detect test pass from recent git/npm activity
    const cwd = process.cwd();
    const packageJson = path.join(cwd, "package.json");
    const hasTests = fs.existsSync(packageJson) &&
      (() => {
        try { return !!JSON.parse(fs.readFileSync(packageJson, "utf8")).scripts?.test; }
        catch (_) { return false; }
      })();

    if (hasTests) {
      process.stdout.write(
        `[TaskCompleted Gate] タスク "${title}" の完了にはテスト通過の証跡が必要です。\n` +
        `completion_notes に「テスト XX 件通過」などテスト結果を記載するか、` +
        `実際にテストを実行して結果を確認してください。\n`
      );
      process.exit(2);
    }
  }

  process.exit(0);
}

main().catch(e => { console.error(e.message); process.exit(0); });
