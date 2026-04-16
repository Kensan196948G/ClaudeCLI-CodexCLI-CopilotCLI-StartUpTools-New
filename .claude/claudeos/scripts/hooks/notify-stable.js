#!/usr/bin/env node
// notify-stable hook (ClaudeOS v8.2)
// STABLE 達成 / Blocked / 5 時間超過 / Critical Review を Push Notification で通知する。
// Claude Code v2.1.110 以降の Push Notification Tool を経由する想定。
// 通知不可環境では console.log に fallback する。

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

function send(channel, title, body) {
  // Push Notification Tool が CLI 経由で利用可能な場合に備え、まず CLI を試行。
  // 利用不可なら console.log に出力（hook ログ・statusline に反映される）。
  try {
    const { execSync } = require("child_process");
    execSync(
      `claude push-notify --title ${JSON.stringify(title)} --body ${JSON.stringify(body)}`,
      { stdio: "ignore", timeout: 5000 }
    );
    return true;
  } catch {
    console.log(`[Notify:${channel}] ${title} — ${body}`);
    return false;
  }
}

const state = readJson(STATE_FILE);
if (!state) {
  console.log("[NotifyStable] state.json not found — skip");
  process.exit(0);
}

const stable = state.stable || {};
const exec = state.execution || {};
const codex = state.codex || {};
const notif = state.notification || {};
if (!notif.stable && !notif.blocked && !notif.five_hour_end && !notif.critical_review) {
  process.exit(0);
}

const events = [];

// STABLE achieved
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

// Blocked
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

// 5h end
const remaining = exec.remaining_minutes ?? 300;
if (notif.five_hour_end && remaining <= 5) {
  events.push({
    key: "five_hour_end_" + (exec.last_stop_at || ""),
    title: "5h 終了準備",
    body: `残り ${remaining} 分。最終処理を実施`,
  });
}

if (events.length === 0) {
  process.exit(0);
}

const lastKey = notif.last_sent_event || "";
events.forEach((ev) => {
  if (ev.key === lastKey) return; // dedupe per state file
  send(notif.channel || "push", ev.title, ev.body);
  state.notification.last_sent_event = ev.key;
  state.notification.last_sent_at = new Date().toISOString();
});

writeJson(STATE_FILE, state);
process.exit(0);
