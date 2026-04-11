#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

let payload = {};
try {
  const raw = fs.readFileSync(0, 'utf8');
  if (raw && raw.trim()) payload = JSON.parse(raw);
} catch (_) {
  payload = {};
}

const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const anchorPath = path.join(projectDir, '.claude', 'session-anchor.json');
const statePath = path.join(projectDir, 'state.json');
const summaryPath = path.join(projectDir, '.claude', 'session-summary.json');
const historyPath = path.join(projectDir, '.claude', 'session-history.jsonl');

const now = new Date();
const toJstIso = (d) =>
  d.toLocaleString('sv-SE', { timeZone: 'Asia/Tokyo' }).replace(' ', 'T') + '+09:00';
const nowIso = toJstIso(now);

let anchor = null;
try {
  if (fs.existsSync(anchorPath)) {
    anchor = JSON.parse(fs.readFileSync(anchorPath, 'utf8'));
  }
} catch (err) {
  console.error(`[session-end] anchor read failed: ${err.message}`);
}

let state = null;
try {
  if (fs.existsSync(statePath)) {
    state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  }
} catch (err) {
  console.error(`[session-end] state.json read failed: ${err.message}`);
}

const elapsedMin =
  anchor && anchor.wall_clock_start
    ? Math.floor((now - new Date(anchor.wall_clock_start)) / 60000)
    : null;

const summary = {
  schema_version: '1.0',
  session_id: (anchor && anchor.session_id) || payload.session_id || `unknown-${now.getTime()}`,
  ended_at: nowIso,
  wall_clock_start: (anchor && anchor.wall_clock_start) || null,
  wall_clock_deadline: (anchor && anchor.wall_clock_deadline) || null,
  elapsed_minutes: elapsedMin,
  max_duration_minutes: (anchor && anchor.max_duration_minutes) || 300,
  final_phase:
    (state && state.execution && state.execution.phase) ||
    (state && state.status && state.status.current_phase) ||
    'unknown',
  final_loop_number: (state && state.execution && state.execution.loop_number) || null,
  stable: state && state.status ? state.status.stable : null,
  blocked: state && state.status ? state.status.blocked : null,
  learning_counts: {
    failure_patterns:
      (state && state.learning && state.learning.failure_patterns && state.learning.failure_patterns.length) || 0,
    success_patterns:
      (state && state.learning && state.learning.success_patterns && state.learning.success_patterns.length) || 0,
    blocked_patterns:
      (state && state.learning && state.learning.blocked_patterns && state.learning.blocked_patterns.length) || 0,
  },
  reason: payload.reason || payload.hook_event_name || 'SessionEnd',
};

try {
  fs.mkdirSync(path.dirname(summaryPath), { recursive: true });
  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2) + '\n');
  console.log(`[session-end] summary written: ${path.relative(projectDir, summaryPath)}`);
} catch (err) {
  console.error(`[session-end] summary write failed: ${err.message}`);
}

try {
  fs.appendFileSync(historyPath, JSON.stringify(summary) + '\n');
  console.log(`[session-end] history appended: ${path.relative(projectDir, historyPath)}`);
} catch (err) {
  console.error(`[session-end] history append failed: ${err.message}`);
}

try {
  if (state) {
    state.status = state.status || {};
    state.status.last_updated = nowIso;
    state.status.session_ended_at = nowIso;
    if (state.execution) {
      state.execution.elapsed_minutes = elapsedMin;
      state.execution.remaining_minutes =
        elapsedMin !== null ? Math.max(0, (state.execution.max_duration_minutes || 300) - elapsedMin) : null;
    }
    fs.writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
    console.log(`[session-end] state.json finalized`);
  }
} catch (err) {
  console.error(`[session-end] state.json finalize failed: ${err.message}`);
}

console.log(
  `[session-end] elapsed=${elapsedMin}min phase=${summary.final_phase} stable=${summary.stable} blocked=${summary.blocked}`
);
