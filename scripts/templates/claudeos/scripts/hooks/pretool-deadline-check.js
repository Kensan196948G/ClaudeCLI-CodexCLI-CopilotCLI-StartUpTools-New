#!/usr/bin/env node
/*
 * pretool-deadline-check.js — Layer 5 of the 5h time-anchor-protocol.
 *
 * Purpose:
 *   Enforces the 5-hour session deadline at the PreToolUse hook boundary.
 *   When registered in settings.json hooks.PreToolUse, this script runs
 *   before every tool invocation and blocks further tool use once the
 *   session has consumed its full duration.
 *
 * Registration (opt-in, disabled by default):
 *   Add the following to .claude/settings.json hooks block:
 *
 *   "PreToolUse": [
 *     {
 *       "hooks": [
 *         {
 *           "type": "command",
 *           "command": "node \"${CLAUDE_PROJECT_DIR}/.claude/claudeos/scripts/hooks/pretool-deadline-check.js\""
 *         }
 *       ]
 *     }
 *   ]
 *
 * Design principles:
 *   - Fail-open: any error, missing anchor, or parse failure allows the tool
 *     call. The 5h enforcement must never brick a session through hook bugs.
 *   - Advisory warning: when 0 < remaining <= 5 minutes, emit a stderr warning
 *     but allow the call — the operator still needs time to commit and push.
 *   - Hard block: when remaining <= 0, exit 2 with a stderr explanation. The
 *     operator must run the shutdown protocol manually.
 *
 * Exit codes:
 *   0 — allow tool call (silent or with advisory warning)
 *   2 — block tool call (Claude Code interprets exit 2 as hook refusal)
 *
 * Related:
 *   - .claude/claudeos/system/time-anchor-protocol.md (Layer 2 spec)
 *   - .claude/claudeos/scripts/hooks/session-start.js  (Layer 1 anchor writer)
 *   - .claude/claudeos/scripts/hooks/session-end.js    (Layer 4 finalizer)
 */

const fs = require('fs');
const path = require('path');

function failOpen(reason) {
  if (reason) console.error(`[pretool-deadline-check] fail-open: ${reason}`);
  process.exit(0);
}

try {
  try {
    fs.readFileSync(0, 'utf8');
  } catch (_) {
  }

  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const anchorPath = path.join(projectDir, '.claude', 'session-anchor.json');

  if (!fs.existsSync(anchorPath)) {
    failOpen('no session-anchor.json');
  }

  let anchor;
  try {
    anchor = JSON.parse(fs.readFileSync(anchorPath, 'utf8'));
  } catch (err) {
    failOpen(`anchor parse error: ${err.message}`);
  }

  if (!anchor || !anchor.wall_clock_start) {
    failOpen('anchor missing wall_clock_start');
  }

  const start = new Date(anchor.wall_clock_start);
  if (isNaN(start.getTime())) {
    failOpen(`invalid wall_clock_start: ${anchor.wall_clock_start}`);
  }

  const maxMin = typeof anchor.max_duration_minutes === 'number' ? anchor.max_duration_minutes : 300;
  const now = new Date();
  const elapsedMin = Math.floor((now - start) / 60000);
  const remainingMin = maxMin - elapsedMin;

  if (remainingMin <= 0) {
    console.error(
      `[pretool-deadline-check] BLOCK: 5h session deadline reached ` +
        `(elapsed=${elapsedMin}min / max=${maxMin}min). ` +
        `Run the shutdown protocol: commit → push → PR → final summary. ` +
        `Disable this hook temporarily in .claude/settings.json to override.`
    );
    process.exit(2);
  }

  if (remainingMin <= 5) {
    console.error(
      `[pretool-deadline-check] WARN: ${remainingMin} minute(s) remaining until 5h deadline. ` +
        `Finalize session now (commit / push / summary).`
    );
    process.exit(0);
  }

  process.exit(0);
} catch (err) {
  failOpen(`unexpected error: ${err && err.message}`);
}
