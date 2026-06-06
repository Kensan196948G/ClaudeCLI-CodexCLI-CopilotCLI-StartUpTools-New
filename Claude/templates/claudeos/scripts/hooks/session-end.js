#!/usr/bin/env node
// Stop hook (ClaudeOS v9.0)
// セッション終了時に state.json を最終更新し、続けて notify-stable を同期実行する。
// v9.0: learning パターン記録（成功/失敗パターンを state.learning へ追記）を追加。
// 並列実行による state.json への race condition を避けるため、両者は単一 hook エントリに統合する。
// 失敗しても Stop hook をブロックしない fail-soft 設計。
//
// 実行順序: state.json 更新 → learning 記録 → Webhook → notify-stable → Dreaming spawn

const fs = require("fs");
const path = require("path");

// Hook 規約: 診断ログは stderr へ集約し、stdout は hookSpecificOutput JSON 専用にする。
// Stop hook の stdout は Claude Code が JSON としてパースするため、ログが混入すると
// additionalContext (E) が認識されない。本リダイレクトで stdout のクリーン性を保証する。
console.log = (...args) => console.error(...args);

const STATE_FILE = path.join(process.cwd(), "state.json");

// Stop hook 入力 (stdin JSON)。stop_hook_active=true は既に Stop hook 継続中であることを示す
// (Claude Code 標準フィールド)。継続中なら二度目の継続はせず、確実に停止させる。
let STOP_HOOK_ACTIVE = false;
try {
  if (!process.stdin.isTTY) {
    const inp = JSON.parse(fs.readFileSync(0, "utf8") || "{}");
    STOP_HOOK_ACTIVE = inp && inp.stop_hook_active === true;
  }
} catch { /* 入力なし/非JSON時は false (= 通常停止扱い) */ }

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return null;
  }
}

function writeJsonAtomic(file, data) {
  // temp file へ書き込み → rename で atomic 置換。
  // 書き込み中の rip を防ぎ、並列読み込みからの競合を最小化する。
  const tmp = `${file}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + "\n", "utf8");
  fs.renameSync(tmp, file);
}

// --- E (CHANGELOG v2.1.163): Stop hook 継続ゲート -------------------------------
// 本セッションで新規追加された actionable な品質 warning がある場合のみ、会話を 1 回だけ
// 継続させ (hookSpecificOutput.additionalContext)、Claude に停止前の是正を促す。
// ガード: stop_hook_active(継続ループ中) / 1 セッション 1 回上限 / 環境変数で無効化可能。
// これにより「未検証のまま静かに停止」を防ぎつつ、暴走 (無限継続) を構造的に排除する。
// newWarnings = この hook 実行中に push された warning のみ (既存の古い warning は対象外)。
const STOP_CONTINUE_ACTIONABLE = new Set([
  "quality_gate_breach", "tdd_required", "verify_subagent_missing", "audit_fail", "ultrareview_blocker",
]);
function decideStopContinuation(state, stopHookActive, warnCountBefore) {
  if (stopHookActive) return { continue: false };                       // 既に継続中 → 確実に停止
  if (process.env.CLAUDEOS_DISABLE_STOP_CONTINUE) return { continue: false };
  const exec = state.execution || {};
  if ((exec.stop_continue_count || 0) >= 1) return { continue: false }; // 1 セッション 1 回上限
  const all = Array.isArray(state.warnings) ? state.warnings : [];
  const fresh = all.slice(warnCountBefore).filter(w => w && STOP_CONTINUE_ACTIONABLE.has(w.kind));
  if (fresh.length === 0) return { continue: false };
  const kinds = [...new Set(fresh.map(w => w.kind))];
  const message =
    `⚠️ ClaudeOS Stop ゲート: 停止前に未解決の品質課題があります — ${kinds.join(" / ")}。\n` +
    `可能なら本セッション内で是正してください (テスト追加 / lint 修正 / 必須 SubAgent 起動 / ` +
    `ultrareview blocker 対応 等)。是正不能なら Issue 化し、その旨を要約に記録してから停止してください。\n` +
    `(この通知は 1 セッション 1 回のみ。次の停止で確定します。)`;
  return { continue: true, message };
}

let dreamingEnabled = false;

try {
  const state = readJson(STATE_FILE);
  if (state) {
    state.execution = state.execution || {};
    state.execution.last_stop_at = new Date().toISOString();

    // E: この hook 実行で新規 push された warning だけを継続判定に使うため、開始時点の件数を記録
    const _warnCountBefore = Array.isArray(state.warnings) ? state.warnings.length : 0;

    // Dreaming フィールド初期化（初回のみ）
    if (!state.dreaming) {
      state.dreaming = {
        patterns: [],
        curated_memories: [],
        recurring_mistakes: [],
        last_dreaming_run: null,
        dreaming_enabled: false,
      };
    }

    dreamingEnabled = !!state.dreaming.dreaming_enabled;

    // Verify フェーズで必須 SubAgent が起動されたかを検証する。
    // qa / security-reviewer / e2e-runner のいずれも当該セッションで呼ばれていない場合は警告。
    try {
      const exec = state.execution || {};
      const phase = exec.phase;
      if (phase === "Verify") {
        const sessionStart = exec.current_session_start_at;
        const agentHist = ((state.learning || {}).usage_history || {}).agents || {};
        const required = ["qa", "security-reviewer", "e2e-runner"];
        const startMs = sessionStart ? Date.parse(sessionStart) : 0;
        const launched = required.filter((k) => {
          const last = agentHist[k] && agentHist[k].last_used;
          return last && Date.parse(last) >= startMs;
        });
        if (launched.length === 0) {
          state.warnings = state.warnings || [];
          state.warnings.push({
            at: new Date().toISOString(),
            kind: "verify_subagent_missing",
            message: "Verify フェーズで qa / security-reviewer / e2e-runner SubAgent が一度も起動されませんでした。STABLE 判定の必要条件を満たしていない可能性があります。",
            phase,
            required,
          });
          console.log("[SessionEnd][WARN] Verify phase ended without required SubAgent invocation");
        }
      }
    } catch (verifyErr) {
      console.error(`[SessionEnd] verify-subagent-check failed: ${verifyErr.message}`);
    }

    // Quality gate: lint / coverage の閾値違反を state.warnings へ追記する。
    try {
      const qg = require("./quality-gate-check.js");
      const breaches = qg.evaluate(process.cwd(), state);
      if (qg.appendWarnings(state, breaches)) {
        console.log(`[SessionEnd][WARN] Quality gates breached: ${breaches.map(b => b.gate).join(", ")}`);
      }
    } catch (qgErr) {
      if (process.env.CLAUDEOS_DEBUG) console.error(`[SessionEnd] quality-gate skipped: ${qgErr.message}`);
    }

    // Deploy runbook auto-gen: state.deploy.ready=true なら手順書を生成する。
    try {
      if (state.deploy && state.deploy.ready) {
        const { spawnSync } = require("child_process");
        const script = path.join(process.cwd(), "scripts", "release", "generate-deploy-runbook.js");
        if (fs.existsSync(script)) {
          const r = spawnSync(process.execPath, [script], { cwd: process.cwd(), encoding: "utf8" });
          if (r.status === 0) console.log("[SessionEnd] deploy runbook generated (reports/deploy-runbook.md)");
        }
      }
    } catch (drErr) {
      if (process.env.CLAUDEOS_DEBUG) console.error(`[SessionEnd] deploy-runbook skipped: ${drErr.message}`);
    }

    // TDD coverage scan: 直近の変更ファイルに対応テストが無ければ warning 追加。
    try {
      const tdd = require("./tdd-coverage-scan.js");
      const untested = tdd.scan(process.cwd());
      if (untested.length > 0) {
        state.warnings = state.warnings || [];
        state.warnings.push({
          at: new Date().toISOString(),
          kind: "tdd_required",
          message: `テスト未整備の変更が ${untested.length} 件あります。/tdd または tdd-guide agent で対応してください。`,
          files: untested.slice(0, 30),
          truncated: untested.length > 30,
        });
        console.log(`[SessionEnd][WARN] tdd_required: ${untested.length} untested file(s)`);
      }
    } catch (tddErr) {
      if (process.env.CLAUDEOS_DEBUG) console.error(`[SessionEnd] tdd-scan skipped: ${tddErr.message}`);
    }

    // v9.0: learning パターン記録（成功 / 失敗を state.learning へ追記）
    try {
      const stableAchieved = !!(state.stable || {}).stable_achieved;
      const summary = (state.execution || {}).last_session_summary || "";
      const blockedCount = (state.blocked_issues || []).length;
      const warnings = state.warnings || [];

      state.learning = state.learning || { failure_patterns: [], success_patterns: [] };
      state.learning.failure_patterns = state.learning.failure_patterns || [];
      state.learning.success_patterns = state.learning.success_patterns || [];

      if (stableAchieved && summary) {
        // 成功パターン: 直近 20 件を上限として記録
        const entry = { at: new Date().toISOString(), summary: summary.slice(0, 200) };
        state.learning.success_patterns.unshift(entry);
        if (state.learning.success_patterns.length > 20) state.learning.success_patterns.length = 20;
        console.log("[SessionEnd][Learning] success_pattern recorded");
      } else if (blockedCount > 0 || warnings.some(w => w.kind === "verify_subagent_missing")) {
        // 失敗パターン: blocked_issues / verify warning を記録
        const reasons = [
          ...((state.blocked_issues || []).map(b => typeof b === "object" ? b.reason || b.issue || String(b) : String(b))),
          ...warnings.filter(w => w.kind === "verify_subagent_missing").map(w => w.kind),
        ].slice(0, 5);
        const entry = { at: new Date().toISOString(), reasons, summary: summary.slice(0, 200) };
        state.learning.failure_patterns.unshift(entry);
        if (state.learning.failure_patterns.length > 20) state.learning.failure_patterns.length = 20;
        console.log(`[SessionEnd][Learning] failure_pattern recorded (reasons: ${reasons.join(", ")})`);
      }
    } catch (learnErr) {
      if (process.env.CLAUDEOS_DEBUG) console.error(`[SessionEnd] learning-record skipped: ${learnErr.message}`);
    }

    writeJsonAtomic(STATE_FILE, state);
    console.log("[SessionEnd] state.json updated (last_stop_at + learning recorded)");

    // E: Stop 継続ゲート — actionable な新規 warning があれば 1 回だけ会話を継続させる。
    // 継続する場合は finalization(Webhook / notify / Dreaming) を実行せず、最終停止
    // (次回の Stop, stop_hook_active=true) でまとめて 1 回だけ確定させる (二重実行防止)。
    {
      const cont = decideStopContinuation(state, STOP_HOOK_ACTIVE, _warnCountBefore);
      if (cont.continue) {
        state.execution.stop_continue_count = (state.execution.stop_continue_count || 0) + 1;
        writeJsonAtomic(STATE_FILE, state);
        process.stdout.write(JSON.stringify({
          hookSpecificOutput: { hookEventName: "Stop", additionalContext: cont.message },
        }) + "\n");
        console.error("[SessionEnd] Stop 継続: actionable warning 検出 → additionalContext で是正を促し継続");
        process.exit(0);  // finalization は最終停止に委ねる
      }
      if (state.execution.stop_continue_count) {
        state.execution.stop_continue_count = 0;
        writeJsonAtomic(STATE_FILE, state);
      }
    }

    // Webhook: session_end イベントを外部へ通知（detached spawn）
    try {
      const { spawn } = require("child_process");
      const notifier = path.join(__dirname, "webhook-notifier.js");
      if (fs.existsSync(notifier)) {
        const payload = JSON.stringify({
          last_session_summary: (state.execution || {}).last_session_summary || null,
          phase: (state.execution || {}).phase || null,
        });
        const child = spawn(process.execPath, [notifier, "session_end", payload], {
          detached: true,
          stdio: "ignore",
          cwd: process.cwd(),
        });
        child.unref();
      }
    } catch { /* fail-soft */ }
  } else {
    console.log("[SessionEnd] state.json not found — skip");
  }
} catch (err) {
  console.error(`[SessionEnd] state update failed: ${err.message}`);
}

// ReasoningBank: セッション終了時にパターンを保存する（fail-soft）。
// state.json の atomic write が完了した直後に実行し、最新の stable / debug を参照する。
try {
  const rb       = require("./reasoning-bank.js");
  const stateRB  = readJson(STATE_FILE);
  if (stateRB) {
    const projectName = path.basename(process.cwd());
    const dataDir     = path.join(__dirname, "..", "..", "data");
    const bank        = rb.loadBank(dataDir);
    const entry       = rb.buildEntry(stateRB, projectName);
    if (entry) {
      // Stage 2: 既存エントリに SONA 重み更新（時間減衰 + アウトカムデルタ）を適用してから新規追加
      rb.updateSONAWeights(bank, entry.project, entry.tags, entry.stable_achieved);
      rb.upsertEntry(bank, entry);
      rb.pruneBank(bank);
      rb.saveBank(dataDir, bank);
      const sonaUpdated = bank.entries.filter(e => e.id !== entry.id).length;
      console.log(`[ReasoningBank] Saved: ${entry.id} conf=${entry.confidence.toFixed(2)} tags=[${entry.tags.join(",")}] | SONA updated ${sonaUpdated} existing entries`);
    } else {
      // 低信頼でも既存エントリの時間減衰だけは実行する
      const stateRBStab = (stateRB.stable || {});
      const stateRBExec = (stateRB.execution || {});
      const fallbackTags = rb.extractTags(stateRBExec.last_session_summary || "");
      rb.updateSONAWeights(bank, path.basename(process.cwd()), fallbackTags, !!stateRBStab.stable_achieved);
      rb.pruneBank(bank);
      rb.saveBank(dataDir, bank);
      console.log("[ReasoningBank] Entry skipped (confidence < 0.30 or no summary) | SONA decay applied");
    }
  }
} catch (rbErr) {
  console.error(`[ReasoningBank] ${rbErr.message}`);
}

// notify-stable を同期実行する（state.json への書き込みが完了してから）。
// 失敗しても Stop hook をブロックしない。
try {
  const notify = require("./notify-stable.js");
  if (notify && typeof notify.run === "function") {
    notify.run();
  }
} catch (err) {
  console.error(`[SessionEnd] notify-stable failed: ${err.message}`);
}

// Dreaming runner を spawn する。notify-stable の state.json 書き込み完了後に
// 起動することで、dreaming runner が stale な state を上書きするリスクを排除する。
if (dreamingEnabled) {
  try {
    const { spawn } = require("child_process");
    const runner = path.join(__dirname, "dreaming-runner.js");
    if (fs.existsSync(runner)) {
      const child = spawn(process.execPath, [runner], {
        detached: true,
        stdio: "ignore",
        cwd: process.cwd(),
      });
      child.unref(); // 親プロセスの終了をブロックしない
      console.log("[SessionEnd] Dreaming runner spawned (background)");
    }
  } catch (spawnErr) {
    console.error(`[SessionEnd] Dreaming spawn failed: ${spawnErr.message}`);
  }
}

process.exit(0);
