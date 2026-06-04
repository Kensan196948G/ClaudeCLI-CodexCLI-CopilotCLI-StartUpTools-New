#!/usr/bin/env node
// task-created-gate.js — TaskCreated hook
//
// Runs when a task is being created in the shared task list.
// Exit code 2 + message → task creation is rejected with feedback.
// Exit code 0 → task is created normally.
//
// Hook input (stdin JSON):
//   { "task_title": "...", "task_description": "...", "assignee": "..." }

"use strict";

const fs = require("fs");

async function main() {
  let input = {};
  try {
    const raw = fs.readFileSync("/dev/stdin", "utf8").trim();
    if (raw) input = JSON.parse(raw);
  } catch (_) {}

  const title       = (input.task_title || input.title || "").trim();
  const description = (input.task_description || input.description || "").trim();

  // Reject vague tasks
  if (title.length < 5) {
    process.stdout.write(
      `[TaskCreated Gate] タスクタイトルが不明確です: "${title}"\n` +
      `具体的な作業内容（例: "src/auth/login.ts の JWT 検証ロジックを修正"）を記述してください。\n`
    );
    process.exit(2);
  }

  // Reject tasks without acceptance criteria for complex work
  const complexKeywords = ["implement", "refactor", "redesign", "migrate", "実装", "リファクタ", "設計"];
  const isComplex = complexKeywords.some(k => title.toLowerCase().includes(k) || description.toLowerCase().includes(k));
  if (isComplex && description.length < 20) {
    process.stdout.write(
      `[TaskCreated Gate] 複雑なタスクには受入れ基準が必要です。\n` +
      `description に「完了条件」「テスト要件」「影響範囲」を明記してください。\n`
    );
    process.exit(2);
  }

  process.exit(0);
}

main().catch(e => { console.error(e.message); process.exit(0); });
