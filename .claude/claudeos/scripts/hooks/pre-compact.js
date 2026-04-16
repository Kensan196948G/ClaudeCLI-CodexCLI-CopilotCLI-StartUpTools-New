#!/usr/bin/env node
// PreCompact hook (ClaudeOS v8.2)
// 1M context rot 対策として、/compact 実行前に state.json を退避する。
// 退避失敗時は exitCode 2 を返して /compact をブロックする。
// state.json の更新は atomic write (temp + rename) で並列読み書き競合を回避する。

const fs = require("fs");
const path = require("path");

const PROJECT_ROOT = process.cwd();
const STATE_FILE = path.join(PROJECT_ROOT, "state.json");
const SNAPSHOT_DIR = path.join(
  PROJECT_ROOT,
  ".claude",
  "claudeos",
  "snapshots"
);

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

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

function snapshotState() {
  // copyFileSync を直接 try で囲み、TOCTOU リスクを回避する。
  ensureDir(SNAPSHOT_DIR);
  const dest = path.join(SNAPSHOT_DIR, `state.${timestamp()}.json`);
  try {
    fs.copyFileSync(STATE_FILE, dest);
    return { snapshotPath: dest };
  } catch (err) {
    if (err.code === "ENOENT") {
      return { skipped: true, reason: "state.json not found" };
    }
    throw err;
  }
}

function recordCompactTimestamp() {
  const state = readJson(STATE_FILE);
  if (!state) return;
  state.compact = state.compact || {};
  state.compact.last_pre_compact_at = new Date().toISOString();
  writeJsonAtomic(STATE_FILE, state);
}

function pruneOldSnapshots(keep = 20) {
  if (!fs.existsSync(SNAPSHOT_DIR)) return;
  const files = fs
    .readdirSync(SNAPSHOT_DIR)
    .filter((f) => f.startsWith("state.") && f.endsWith(".json"))
    .map((f) => ({
      name: f,
      mtime: fs.statSync(path.join(SNAPSHOT_DIR, f)).mtimeMs,
    }))
    .sort((a, b) => b.mtime - a.mtime);
  files.slice(keep).forEach((f) =>
    fs.unlinkSync(path.join(SNAPSHOT_DIR, f.name))
  );
}

try {
  const result = snapshotState();
  recordCompactTimestamp();
  pruneOldSnapshots(20);

  if (result.skipped) {
    console.log(`[PreCompact] skipped: ${result.reason}`);
  } else {
    console.log(`[PreCompact] state snapshot saved: ${result.snapshotPath}`);
  }
  process.exit(0);
} catch (err) {
  console.error(`[PreCompact] FAILED: ${err.message}`);
  // exitCode 2 = block /compact (Claude Code hook spec)
  process.exit(2);
}
