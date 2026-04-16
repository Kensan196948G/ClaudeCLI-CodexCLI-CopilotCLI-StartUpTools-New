#!/usr/bin/env node
// notify-stable hook (ClaudeOS v8.2)
// STABLE 達成 / Blocked / 5 時間超過 / Critical Review を Push Notification で通知する。
// Claude Code v2.1.110 以降の Push Notification Tool を経由する想定。
// 通知不可環境では console.log に fallback する。
//
// このモジュールは session-end.js から require されて同期実行される。
// Stop hooks の並列実行で state.json への race condition が発生するのを避けるため、
// settings.json には独立した hook エントリを置かない。

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

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

function send(channel, title, body) {
  // execFileSync を使い shell 解釈を回避する (Windows / Linux 共通の安全策)。
  // CLI が無い場合は console.log に fallback する。
  try {
    execFileSync(
      "claude",
      ["push-notify", "--title", title, "--body", body],
      { stdio: "ignore", timeout: 5000 }
    );
    return true;
  } catch {
    console.log(`[Notify:${channel}] ${title} — ${body}`);
    return false;
  }
}

function collectEvents(state) {
  const stable = state.stable || {};
  const exec = state.execution || {};
  const codex = state.codex || {};
  const notif = state.notification || {};
  const events = [];

  if (
    notif.stable &&
    stable.stable_achieved &&
    notif.last_sent_event !== "stable_" + (stable.last_verified_at || "")
  ) {
    events.push({
      key: "stable_" + (stable.last_verified_at || ""),
      title: "STABLE 達成",
      body: `PR #${stable.stable_achieved_pr ?? "?"} merge 可能`,
    });
  }

  if (
    notif.blocked &&
    (codex.severity === "high" || (codex.blocking_issues || []).length > 0)
  ) {
    events.push({
      key: "blocked_" + JSON.stringify(codex.blocking_issues || []),
      title: "Blocked",
      body: `severity=${codex.severity}, issues=${(codex.blocking_issues || []).length}`,
    });
  }

  if (
    notif.critical_review &&
    (codex.severity === "high" || codex.severity === "critical")
  ) {
    const reviewKey =
      "critical_review_" + (codex.last_review_job_id || codex.severity);
    if (notif.last_sent_event !== reviewKey) {
      events.push({
        key: reviewKey,
        title: "Critical Review",
        body: `Codex/CodeRabbit severity=${codex.severity}, job=${codex.last_review_job_id || "(none)"}`,
      });
    }
  }

  const remaining = exec.remaining_minutes ?? 300;
  if (notif.five_hour_end && remaining <= 5) {
    events.push({
      key: "five_hour_end_" + (exec.last_stop_at || ""),
      title: "5h 終了準備",
      body: `残り ${remaining} 分。最終処理を実施`,
    });
  }

  return events;
}

function run() {
  const state = readJson(STATE_FILE);
  if (!state) {
    console.log("[NotifyStable] state.json not found — skip");
    return;
  }

  const notif = state.notification || {};
  if (
    !notif.stable &&
    !notif.blocked &&
    !notif.five_hour_end &&
    !notif.critical_review
  ) {
    return;
  }

  const events = collectEvents(state);
  if (events.length === 0) return;

  const lastKey = notif.last_sent_event || "";
  let updated = false;
  events.forEach((ev) => {
    if (ev.key === lastKey) return;
    send(notif.channel || "push", ev.title, ev.body);
    state.notification.last_sent_event = ev.key;
    state.notification.last_sent_at = new Date().toISOString();
    updated = true;
  });

  if (updated) writeJson(STATE_FILE, state);
}

if (require.main === module) {
  try {
    run();
    process.exit(0);
  } catch (err) {
    console.error(`[NotifyStable] error: ${err.message}`);
    process.exit(0); // never block Stop hook
  }
}

module.exports = { run, collectEvents };
