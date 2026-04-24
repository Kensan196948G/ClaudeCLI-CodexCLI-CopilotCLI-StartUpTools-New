#!/usr/bin/env node
// Stop hook (ClaudeOS v8.2)
// セッション終了時に state.json を最終更新し、続けて notify-stable を同期実行する。
// 並列実行による state.json への race condition を避けるため、両者は単一 hook エントリに統合する。
// 失敗しても Stop hook をブロックしない fail-soft 設計。

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
  // temp file へ書き込み → rename で atomic 置換。
  // 書き込み中の rip を防ぎ、並列読み込みからの競合を最小化する。
  const tmp = `${file}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + "\n", "utf8");
  fs.renameSync(tmp, file);
}

try {
  const state = readJson(STATE_FILE);
  if (state) {
    state.execution = state.execution || {};
    state.execution.last_stop_at = new Date().toISOString();
    writeJsonAtomic(STATE_FILE, state);
    console.log("[SessionEnd] state.json updated (last_stop_at recorded)");
  } else {
    console.log("[SessionEnd] state.json not found — skip");
  }
} catch (err) {
  console.error(`[SessionEnd] state update failed: ${err.message}`);
}

// 続けて notify-stable を同期実行する。失敗しても Stop hook をブロックしない。
try {
  const notify = require("./notify-stable.js");
  if (notify && typeof notify.run === "function") {
    notify.run();
  }
} catch (err) {
  console.error(`[SessionEnd] notify-stable failed: ${err.message}`);
}

// v3.2.81: Managed Memory Store sync (push) — config が存在する場合のみ (opt-in)
// Stop フック内ではブロッキング呼び出しが ETIMEDOUT になるため spawn detached で非同期起動する
(function syncMemoryStorePush() {
  const { spawn } = require("child_process");
  const cfgPath = path.join(process.cwd(), "config", "managed-agents.json");
  const memPy = path.join(process.cwd(), "scripts", "tools", "managed-memory.py");
  if (!fs.existsSync(cfgPath) || !fs.existsSync(memPy)) return;

  const python = process.platform === "win32" ? "C:\\Python314\\python.exe" : "python3";
  const logPath = path.join(process.cwd(), "logs", "memory-push.log");
  try {
    fs.mkdirSync(path.dirname(logPath), { recursive: true });
    const logFd = fs.openSync(logPath, "a");
    const child = spawn(python, [memPy, "sync", "--direction", "push"], {
      env: { ...process.env, MANAGED_AGENTS_CONFIG: cfgPath },
      detached: true,
      stdio: ["ignore", logFd, logFd],
    });
    child.unref();
    console.log(`  memory_sync: push launched (background → ${logPath})`);
  } catch (e) {
    console.log(`  memory_sync: push launch failed — ${e.message}`);
  }
})();

process.exit(0);
