#!/usr/bin/env node
// Stop hook (ClaudeOS v8.2)
// セッション終了時に state.json を最終更新する。
// notify-stable.js とは別 hook として並列実行される。

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

function writeJson(file, data) {
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n", "utf8");
}

const state = readJson(STATE_FILE);
if (!state) {
  console.log("[SessionEnd] state.json not found — skip");
  process.exit(0);
}

state.execution = state.execution || {};
state.execution.last_stop_at = new Date().toISOString();

writeJson(STATE_FILE, state);
console.log("[SessionEnd] state.json updated (last_stop_at recorded)");
process.exit(0);
