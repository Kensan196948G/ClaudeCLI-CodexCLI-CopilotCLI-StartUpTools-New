#!/usr/bin/env node
// stop-continue-gate.js — Stop hook 継続ゲートの判定ロジック (CHANGELOG v2.1.163)
// ---------------------------------------------------------------------------
// session-end.js から require される。副作用を持たない純粋判定として分離し、
// scripts/test/test-stop-continue-gate.js から独立してユニットテスト可能にする。
//
// 仕様: 本セッションで「新規に」追加された actionable な品質 warning があり、かつ
//       継続ループ中でなく (stop_hook_active=false)、1 セッション 1 回上限に達して
//       いない場合のみ continue=true を返し、停止前の是正を促すメッセージを添える。
// ---------------------------------------------------------------------------
"use strict";

const STOP_CONTINUE_ACTIONABLE = new Set([
  "quality_gate_breach", "tdd_required", "verify_subagent_missing", "audit_fail", "ultrareview_blocker",
]);

/**
 * @param {object} state            state.json オブジェクト
 * @param {boolean} stopHookActive  Stop hook 入力の stop_hook_active (継続ループ中フラグ)
 * @param {number} warnCountBefore  この hook 実行開始時点の state.warnings 件数
 * @returns {{continue:boolean, message?:string}}
 */
function decideStopContinuation(state, stopHookActive, warnCountBefore) {
  if (stopHookActive) return { continue: false };                       // 既に継続中 → 確実に停止
  if (process.env.CLAUDEOS_DISABLE_STOP_CONTINUE) return { continue: false }; // 脱出弁
  const exec = (state && state.execution) || {};
  if ((exec.stop_continue_count || 0) >= 1) return { continue: false }; // 1 セッション 1 回上限
  const all = Array.isArray(state && state.warnings) ? state.warnings : [];
  const fresh = all.slice(warnCountBefore || 0).filter(w => w && STOP_CONTINUE_ACTIONABLE.has(w.kind));
  if (fresh.length === 0) return { continue: false };
  const kinds = [...new Set(fresh.map(w => w.kind))];
  const message =
    `⚠️ ClaudeOS Stop ゲート: 停止前に未解決の品質課題があります — ${kinds.join(" / ")}。\n` +
    `可能なら本セッション内で是正してください (テスト追加 / lint 修正 / 必須 SubAgent 起動 / ` +
    `ultrareview blocker 対応 等)。是正不能なら Issue 化し、その旨を要約に記録してから停止してください。\n` +
    `(この通知は 1 セッション 1 回のみ。次の停止で確定します。)`;
  return { continue: true, message };
}

module.exports = { decideStopContinuation, STOP_CONTINUE_ACTIONABLE };
