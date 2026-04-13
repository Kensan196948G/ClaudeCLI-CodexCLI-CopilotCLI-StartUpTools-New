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

const now = new Date();
const plus5 = new Date(now.getTime() + 5 * 60 * 60 * 1000);
const toJstIso = (d) =>
  d.toLocaleString('sv-SE', { timeZone: 'Asia/Tokyo' }).replace(' ', 'T') + '+09:00';

const wallClockStart = toJstIso(now);
const wallClockDeadline = toJstIso(plus5);

const sessionId =
  payload.session_id ||
  `fallback-${now.toISOString().replace(/[:.TZ-]/g, '').slice(0, 14)}`;

const anchor = {
  session_id: sessionId,
  source: payload.source || payload.hook_event_name || 'SessionStart',
  wall_clock_start: wallClockStart,
  wall_clock_deadline: wallClockDeadline,
  max_duration_minutes: 300,
  written_by: 'session-start.js',
  written_at: wallClockStart,
  note: 'Immutable during this session. Derived elapsed/remaining are written to state.json.execution on each loop.',
};

try {
  fs.mkdirSync(path.dirname(anchorPath), { recursive: true });
  fs.writeFileSync(anchorPath, JSON.stringify(anchor, null, 2) + '\n');
  console.log(`[session-start] anchored start=${wallClockStart} deadline=${wallClockDeadline}`);
} catch (err) {
  console.error(`[session-start] anchor write failed: ${err.message}`);
  process.exit(0);
}

try {
  if (!fs.existsSync(statePath)) return;
  const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  state.execution = state.execution || {};
  state.execution.start_time = wallClockStart;
  state.execution.end_time = wallClockDeadline;
  state.execution.max_duration_minutes = 300;
  state.execution.elapsed_minutes = 0;
  state.execution.remaining_minutes = 300;
  state.status = state.status || {};
  state.status.last_updated = wallClockStart;
  fs.writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
  console.log(`[session-start] state.json execution block synchronized to anchor`);
} catch (err) {
  console.error(`[session-start] state.json sync skipped: ${err.message}`);
}
