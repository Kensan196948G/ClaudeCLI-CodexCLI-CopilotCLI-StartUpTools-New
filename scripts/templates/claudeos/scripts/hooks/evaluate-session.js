#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const anchorPath = path.join(projectDir, '.claude', 'session-anchor.json');
const statePath = path.join(projectDir, 'state.json');
const summaryPath = path.join(projectDir, '.claude', 'session-summary.json');
const evalPath = path.join(projectDir, '.claude', 'session-evaluation.json');

const now = new Date();
const toJstIso = (d) =>
  d.toLocaleString('sv-SE', { timeZone: 'Asia/Tokyo' }).replace(' ', 'T') + '+09:00';

let anchor = null;
let state = null;
let summary = null;
try {
  if (fs.existsSync(anchorPath)) anchor = JSON.parse(fs.readFileSync(anchorPath, 'utf8'));
} catch (_) {}
try {
  if (fs.existsSync(statePath)) state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
} catch (_) {}
try {
  if (fs.existsSync(summaryPath)) summary = JSON.parse(fs.readFileSync(summaryPath, 'utf8'));
} catch (_) {}

if (!anchor && !state) {
  console.error('[evaluate-session] no anchor or state available, skipping');
  process.exit(0);
}

const maxMin = (anchor && anchor.max_duration_minutes) || (state && state.execution && state.execution.max_duration_minutes) || 300;
const elapsedMin =
  anchor && anchor.wall_clock_start
    ? Math.floor((now - new Date(anchor.wall_clock_start)) / 60000)
    : (state && state.execution && state.execution.elapsed_minutes) || 0;
const usagePct = Math.round((elapsedMin / maxMin) * 100);

const timePhase =
  usagePct >= 95 ? 'RED' : usagePct >= 85 ? 'ORANGE' : usagePct >= 70 ? 'YELLOW' : 'GREEN';

const kpi = {
  elapsed_minutes: elapsedMin,
  max_minutes: maxMin,
  usage_pct: usagePct,
  time_phase: timePhase,
  stable: state && state.status ? state.status.stable : null,
  blocked: state && state.status ? state.status.blocked : null,
  current_phase:
    (state && state.execution && state.execution.phase) ||
    (state && state.status && state.status.current_phase) ||
    'unknown',
  learning_growth: {
    failure:
      (state && state.learning && state.learning.failure_patterns && state.learning.failure_patterns.length) || 0,
    success:
      (state && state.learning && state.learning.success_patterns && state.learning.success_patterns.length) || 0,
  },
  debug_retry:
    (state && state.debug && state.debug.same_error_retry_count) || 0,
  codex_review:
    (state && state.codex && state.codex.last_review_status) || 'none',
};

const learnings = [];
if (state && state.learning && Array.isArray(state.learning.failure_patterns)) {
  learnings.push(
    ...state.learning.failure_patterns.slice(-3).map((p) => ({ type: 'failure', pattern: p }))
  );
}
if (state && state.learning && Array.isArray(state.learning.success_patterns)) {
  learnings.push(
    ...state.learning.success_patterns.slice(-3).map((p) => ({ type: 'success', pattern: p }))
  );
}

const hints = [
  kpi.blocked ? 'Blocked state detected — investigate before new work' : null,
  kpi.time_phase === 'GREEN' && kpi.usage_pct < 20
    ? 'Low session utilization — consider deeper work next time'
    : null,
  kpi.debug_retry >= 2 ? 'Debug retry count elevated — review failure_patterns' : null,
  kpi.codex_review === 'completed' ? 'Codex review completed — safe to merge' : null,
  kpi.time_phase === 'RED' ? 'Time budget exhausted — hard stop required' : null,
].filter(Boolean);

const evaluation = {
  schema_version: '1.0',
  evaluated_at: toJstIso(now),
  session_id: (anchor && anchor.session_id) || (summary && summary.session_id) || 'unknown',
  kpi,
  recent_learnings: learnings,
  next_session_hints: hints,
};

try {
  fs.mkdirSync(path.dirname(evalPath), { recursive: true });
  fs.writeFileSync(evalPath, JSON.stringify(evaluation, null, 2) + '\n');
  console.log(`[evaluate-session] evaluation written: ${path.relative(projectDir, evalPath)}`);
} catch (err) {
  console.error(`[evaluate-session] write failed: ${err.message}`);
  process.exit(0);
}

console.log(
  `[evaluate-session] usage=${usagePct}% time=${timePhase} phase=${kpi.current_phase} learnings=${learnings.length}`
);
