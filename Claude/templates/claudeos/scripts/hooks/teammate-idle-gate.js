#!/usr/bin/env node
// teammate-idle-gate.js — TeammateIdle hook
//
// Runs when a teammate is about to go idle.
// Exit code 2 + feedback message → teammate keeps working with the feedback.
// Exit code 0 → teammate goes idle normally.
//
// Hook input (stdin JSON):
//   { "session_id": "...", "teammate_name": "...", "last_message": "..." }

"use strict";

const fs = require("fs");
const path = require("path");

async function main() {
  let input = {};
  try {
    const raw = fs.readFileSync("/dev/stdin", "utf8").trim();
    if (raw) input = JSON.parse(raw);
  } catch (_) {}

  const teammateName = input.teammate_name || input.session_id || "unknown";
  const lastMessage  = (input.last_message || "").toLowerCase();

  // Quality gate: if the teammate's last message suggests incomplete work, keep them working
  const incompleteSignals = [
    "i'll leave",
    "you can proceed",
    "feel free to",
    "let me know if",
    "i'm done here",
    "that should be",
  ];

  const hasIncompleteSignal = incompleteSignals.some(s => lastMessage.includes(s));

  // Check if there are open tasks in the shared task list
  const taskDirs = [
    path.join(process.env.HOME || "/root", ".claude", "tasks"),
  ];
  let openTaskCount = 0;
  for (const taskDir of taskDirs) {
    if (fs.existsSync(taskDir)) {
      try {
        const files = fs.readdirSync(taskDir, { recursive: true });
        const pendingFiles = files.filter(f => f.toString().endsWith(".json"));
        for (const f of pendingFiles) {
          try {
            const fullPath = path.join(taskDir, f.toString());
            const task = JSON.parse(fs.readFileSync(fullPath, "utf8"));
            if (task.status === "pending" || task.status === "in_progress") openTaskCount++;
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  // Allow idle if no signals and no open tasks
  if (!hasIncompleteSignal && openTaskCount === 0) {
    process.exit(0);
  }

  // Keep working if incomplete signals detected
  if (hasIncompleteSignal) {
    process.stdout.write(
      `[TeammateIdle Gate] ${teammateName}: 作業が完結していない可能性があります。` +
      `タスクの完了基準を確認し、残作業があれば継続してください。` +
      `問題なく完了している場合は明示的に「作業完了」と報告してください。\n`
    );
    process.exit(2);
  }

  process.exit(0);
}

main().catch(e => { console.error(e.message); process.exit(0); });
