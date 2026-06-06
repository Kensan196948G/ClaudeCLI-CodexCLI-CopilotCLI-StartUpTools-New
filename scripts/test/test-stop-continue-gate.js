#!/usr/bin/env node
// test-stop-continue-gate.js — E (Stop hook 継続ゲート) 判定ロジックの回帰テスト。
// CI の「Node validations」ステップから `node scripts/test/test-stop-continue-gate.js` で実行。
// 失敗時は exit 1。CHANGELOG v2.1.163 取り込み (#347) の安全性ガードを検証する。
"use strict";

const path = require("path");
const GATE = path.join(__dirname, "..", "..", ".claude", "claudeos", "scripts", "hooks", "stop-continue-gate.js");
const { decideStopContinuation, STOP_CONTINUE_ACTIONABLE } = require(GATE);

// テスト中は脱出弁 env を確実に未設定にする
delete process.env.CLAUDEOS_DISABLE_STOP_CONTINUE;

let failed = 0;
function check(name, cond) {
  if (cond) { console.log(`  ✅ ${name}`); }
  else { console.error(`  ❌ ${name}`); failed++; }
}

const freshWarn = (kind) => ({ kind, at: new Date().toISOString(), message: "x" });

console.log("🧪 stop-continue-gate 判定ロジック");

// 1. 新規 actionable warning + 継続中でない + 上限未満 → 継続する
{
  const state = { execution: { stop_continue_count: 0 }, warnings: [freshWarn("tdd_required")] };
  const r = decideStopContinuation(state, false, 0);
  check("新規 tdd_required で継続する", r.continue === true);
  check("継続メッセージに kind を含む", typeof r.message === "string" && r.message.includes("tdd_required"));
}

// 2. stop_hook_active=true → 継続しない (継続ループ防止)
{
  const state = { execution: { stop_continue_count: 0 }, warnings: [freshWarn("tdd_required")] };
  check("stop_hook_active=true で継続しない", decideStopContinuation(state, true, 0).continue === false);
}

// 3. 既に 1 回継続済み (count>=1) → 継続しない (1 セッション 1 回上限)
{
  const state = { execution: { stop_continue_count: 1 }, warnings: [freshWarn("audit_fail")] };
  check("count>=1 で継続しない", decideStopContinuation(state, false, 0).continue === false);
}

// 4. actionable warning なし → 継続しない
{
  const state = { execution: {}, warnings: [] };
  check("warning 無しで継続しない", decideStopContinuation(state, false, 0).continue === false);
}

// 5. actionable でない kind の warning → 継続しない
{
  const state = { execution: {}, warnings: [freshWarn("some_info")] };
  check("非 actionable kind で継続しない", decideStopContinuation(state, false, 0).continue === false);
}

// 6. warnCountBefore より前の (既存) warning は対象外 — 新規が非 actionable なら継続しない
{
  const state = { execution: {}, warnings: [freshWarn("tdd_required"), freshWarn("some_info")] };
  // index 0 は既存(=warnCountBefore=1 で除外)、index 1 が新規(非actionable) → 継続しない
  check("warnCountBefore で既存 warning を除外する", decideStopContinuation(state, false, 1).continue === false);
}

// 7. CLAUDEOS_DISABLE_STOP_CONTINUE 設定時 → 継続しない (脱出弁)
{
  process.env.CLAUDEOS_DISABLE_STOP_CONTINUE = "1";
  const state = { execution: { stop_continue_count: 0 }, warnings: [freshWarn("verify_subagent_missing")] };
  check("DISABLE env で継続しない", decideStopContinuation(state, false, 0).continue === false);
  delete process.env.CLAUDEOS_DISABLE_STOP_CONTINUE;
}

// 8. actionable kind 集合の健全性
check("actionable 集合に主要 kind を含む",
  ["quality_gate_breach", "tdd_required", "verify_subagent_missing", "audit_fail", "ultrareview_blocker"]
    .every(k => STOP_CONTINUE_ACTIONABLE.has(k)));

if (failed) { console.error(`\n❌ ${failed} 件失敗`); process.exit(1); }
console.log("\n✅ stop-continue-gate: 全テスト通過");
