#!/usr/bin/env node
// SessionStart hook (ClaudeOS v8.2)
// 起動時に state.json を読み、前回セッションの再開ヒントを表示する。
// /recap が利用できない環境での代替経路としても機能する。

const fs = require("fs");
const path = require("path");

const STATE_FILE = path.join(process.cwd(), "state.json");

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

const state = readJson(STATE_FILE);
if (!state) {
  console.log("[SessionStart] state.json not found — fresh session");
  process.exit(0);
}

const exec = state.execution || {};
const stable = state.stable || {};
const token = state.token || {};
const compact = state.compact || {};

console.log("[SessionStart] ClaudeOS v8.2 resume context");
console.log(`  phase: ${exec.phase || "unknown"}`);
console.log(`  last_summary: ${exec.last_session_summary || "(none)"}`);
console.log(`  stable_achieved: ${stable.stable_achieved ? "yes" : "no"}`);
console.log(`  consecutive_success: ${stable.consecutive_success ?? 0}`);
console.log(
  `  token: used=${token.used ?? 0}% / remaining=${token.remaining ?? 100}%`
);
console.log(`  last_pre_compact_at: ${compact.last_pre_compact_at || "(never)"}`);

process.exit(0);
