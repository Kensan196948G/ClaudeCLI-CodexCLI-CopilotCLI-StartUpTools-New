#!/usr/bin/env node
// SessionStart hook (ClaudeOS v8.2)
// 起動時に state.json を読み、前回セッションの再開ヒントを表示する。
// また、current_session_start_at を書き込み、セッション追跡を確立する。
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

function writeJsonAtomic(file, data) {
  const tmp = `${file}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + "\n", "utf8");
  fs.renameSync(tmp, file);
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

// P1-5: state.json に current_session_start_at を書き込む（display-only → write 昇格）
try {
  const now = new Date().toISOString();
  state.execution = exec;
  state.execution.current_session_start_at = now;

  // cron 起動の場合は trigger を記録（CLAUDE_SESSION_ID env var が存在する）
  const cronSessionId = process.env.CLAUDE_SESSION_ID;
  if (cronSessionId) {
    state.execution.last_trigger = "cron";
    state.execution.last_cron_session_id = cronSessionId;
  } else {
    state.execution.last_trigger = "manual";
  }

  writeJsonAtomic(STATE_FILE, state);
  console.log(`  session_start_at: ${now}`);
  console.log(`  trigger: ${state.execution.last_trigger}`);
} catch (err) {
  // 書き込み失敗は無視（表示は完了しているため）
  console.error(`[SessionStart] state.json write failed: ${err.message}`);
}

process.exit(0);
