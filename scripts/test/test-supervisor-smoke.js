'use strict';
// test-supervisor-smoke.js — CI smoke test for supervisor-daemon.js
// Spawns the daemon with a minimal session-file config (no subprocess side effects),
// verifies state.json is written with the correct structure, then kills it.
// Runs on both Linux (ubuntu CI) and Windows.

const fs   = require('fs');
const path = require('path');
const os   = require('os');
const { spawn } = require('child_process');

const DAEMON     = path.resolve(__dirname, '..', 'dashboards', 'supervisor-daemon.js');
const TIMEOUT_MS = 6000;

function fatal(msg) {
  process.stderr.write(`FAIL: ${msg}\n`);
  process.exit(1);
}

function assert(cond, msg) {
  if (!cond) fatal(msg);
}

async function run() {
  // ── Temp workspace ─────────────────────────────────────────────────────────
  const tmpDir    = fs.mkdtempSync(path.join(os.tmpdir(), 'sup-smoke-'));
  const procsCfg  = path.join(tmpDir, 'processes.json');
  const stateFile = path.join(tmpDir, 'state.json');

  // ── Minimal config: session-file only (daemon reads files, never spawns) ──
  const cfg = {
    version: '1.0.0',
    processes: [
      {
        id: 'smoke-session',
        type: 'session-file',
        name: 'Smoke Test Session',
        sessionDir: tmpDir,
        staleMinutes: 60,
        enabled: true,
      },
    ],
  };
  fs.writeFileSync(procsCfg, JSON.stringify(cfg, null, 2), 'utf8');

  // ── Spawn daemon ───────────────────────────────────────────────────────────
  const child = spawn(process.execPath, [DAEMON], {
    env: {
      ...process.env,
      SUPERVISOR_PROCESSES_CFG: procsCfg,
      SUPERVISOR_STATE_DIR:     tmpDir,
      SUPERVISOR_STATE_FILE:    stateFile,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let output = '';
  child.stdout.on('data', d => { output += d; });
  child.stderr.on('data', d => { output += d; });

  // ── Wait for initial state.json (written at startup before first tick) ────
  const deadline = Date.now() + TIMEOUT_MS;
  while (!fs.existsSync(stateFile) && Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 50));
  }

  // ── Terminate daemon ───────────────────────────────────────────────────────
  child.kill('SIGTERM');
  await new Promise(resolve => child.on('exit', resolve));

  // ── Validate state.json ────────────────────────────────────────────────────
  assert(fs.existsSync(stateFile), `state.json was not created within ${TIMEOUT_MS}ms`);

  let state;
  try {
    state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  } catch (e) {
    fatal(`state.json is not valid JSON: ${e.message}`);
  }

  assert(state.version === '1.0.0', `expected version '1.0.0', got '${state.version}'`);
  assert(typeof state.generated === 'string' && state.generated.length > 0,
    'state.generated should be a non-empty ISO string');
  assert(typeof state.processes === 'object' && state.processes !== null,
    'state.processes should be an object');
  assert('smoke-session' in state.processes,
    "state.processes should contain 'smoke-session' entry");

  const entry = state.processes['smoke-session'];
  assert(typeof entry.status === 'string', 'process entry must have a status field');
  assert(entry.type === 'session-file', `expected type 'session-file', got '${entry.type}'`);
  assert(entry.name === 'Smoke Test Session', `unexpected name: ${entry.name}`);

  // ── Cleanup ────────────────────────────────────────────────────────────────
  fs.rmSync(tmpDir, { recursive: true, force: true });

  process.stdout.write('PASS: supervisor-daemon smoke test\n');
}

run().catch(e => fatal(e.stack || e.message));
