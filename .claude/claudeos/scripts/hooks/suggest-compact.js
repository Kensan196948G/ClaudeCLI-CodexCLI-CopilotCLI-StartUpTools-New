#!/usr/bin/env node
// suggest-compact (ClaudeOS v8.2)
// state.json の token / compact / stable を見て、/compact 推奨タイミングを判定する。
// CLAUDE.md §12 の事前発動規約をプログラム化したもの。

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
  console.log("[SuggestCompact] state.json not found");
  process.exit(0);
}

const token = state.token || {};
const debug = state.debug || {};
const exec = state.execution || {};
const compact = state.compact || {};

const reasons = [];
const usedPct = token.used ?? 0;
const trigger = compact.trigger_at_pct ?? 70;

if (usedPct >= trigger) {
  reasons.push(
    `Token usage ${usedPct}% >= ${trigger}% — recommend /compact with hint: "Keep STABLE checklist, current PR diff, last 3 hypotheses"`
  );
}

if (
  (debug.same_error_retry_count ?? 0) >= (compact.verify_failure_threshold ?? 3)
) {
  reasons.push(
    `Verify failure ${debug.same_error_retry_count}x — recommend /compact with hint: "Keep failed test logs, root cause hypothesis, last 2 commits"`
  );
}

const elapsed = exec.elapsed_minutes ?? 0;
const longThreshold = compact.long_session_minutes ?? 120;
if (elapsed >= longThreshold) {
  reasons.push(
    `Session ${elapsed}min >= ${longThreshold}min — recommend /compact with hint: "Keep session goal, STABLE state, blocking issues"`
  );
}

if (reasons.length === 0) {
  console.log("[SuggestCompact] no compaction needed");
} else {
  console.log("[SuggestCompact] /compact RECOMMENDED:");
  reasons.forEach((r, i) => console.log(`  ${i + 1}. ${r}`));
}

process.exit(0);
