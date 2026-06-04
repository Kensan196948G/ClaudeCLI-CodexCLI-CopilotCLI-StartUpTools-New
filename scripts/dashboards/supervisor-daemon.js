'use strict';
// supervisor-daemon.js — ClaudeOS Process Supervisor v1.0.0
// Node.js built-ins only (no npm deps). Win32 / Linux both supported.
// Reads:  config/processes.json
// Writes: ~/.claudeos/supervisor/state.json (atomically)
// Launched by: Task Scheduler (Windows) or systemd user service (Linux)

const fs   = require('fs');
const path = require('path');
const http = require('http');
const os   = require('os');
const { spawn } = require('child_process');

// ── Paths ────────────────────────────────────────────────────────────────────
const PROJ_ROOT      = path.resolve(__dirname, '..', '..');
const PROCESSES_CFG  = path.join(PROJ_ROOT, 'config', 'processes.json');
const SUPERVISOR_DIR = path.join(os.homedir(), '.claudeos', 'supervisor');
const STATE_FILE     = path.join(SUPERVISOR_DIR, 'state.json');

// ── Constants ────────────────────────────────────────────────────────────────
const CHECK_INTERVAL_MS  = 8000;   // main loop cadence
const MAX_COOLDOWN_SEC   = 300;    // exponential backoff ceiling
const LOG_PREFIX         = '[supervisor]';

// ── Runtime state ─────────────────────────────────────────────────────────────
// processState: { [id]: ProcessEntry }
const processState = {};
// childHandles: { [id]: ChildProcess }
const childHandles = {};

// ── Logging ──────────────────────────────────────────────────────────────────
function log(msg) {
  process.stdout.write(`${LOG_PREFIX} ${new Date().toISOString()} ${msg}\n`);
}

// ── Path template expansion ──────────────────────────────────────────────────
function expandPath(str) {
  if (typeof str !== 'string') return str;
  return str
    .replace('${PROJ_ROOT}', PROJ_ROOT)
    .replace('${HOME}', os.homedir())
    .replace('~', os.homedir());
}

// ── Config loader ────────────────────────────────────────────────────────────
function loadConfig() {
  try {
    const raw = fs.readFileSync(PROCESSES_CFG, 'utf8');
    const cfg = JSON.parse(raw);
    return (cfg.processes || []).filter(p => p.enabled !== false);
  } catch (e) {
    log(`ERROR: cannot load ${PROCESSES_CFG}: ${e.message}`);
    return [];
  }
}

// ── Atomic state write ───────────────────────────────────────────────────────
function writeState() {
  try {
    if (!fs.existsSync(SUPERVISOR_DIR)) fs.mkdirSync(SUPERVISOR_DIR, { recursive: true });
    const snapshot = {
      version:   '1.0.0',
      generated: new Date().toISOString(),
      processes: processState,
    };
    const tmp = STATE_FILE + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(snapshot, null, 2), 'utf8');
    fs.renameSync(tmp, STATE_FILE);
  } catch (e) {
    log(`WARN: failed to write state: ${e.message}`);
  }
}

// ── PID liveness check ───────────────────────────────────────────────────────
function isPidAlive(pid) {
  if (!pid) return false;
  try { process.kill(pid, 0); return true; } catch { return false; }
}

// ── HTTP health check (returns Promise<boolean>) ─────────────────────────────
function checkHttp(url) {
  return new Promise(resolve => {
    const timeout = setTimeout(() => { try { req.destroy(); } catch {} resolve(false); }, 4000);
    const req = http.get(url, res => {
      clearTimeout(timeout);
      res.resume();
      resolve(res.statusCode >= 200 && res.statusCode < 400);
    });
    req.on('error', () => { clearTimeout(timeout); resolve(false); });
  });
}

// ── Exponential backoff cooldown (seconds) ───────────────────────────────────
function cooldownSec(base, failures) {
  return Math.min(base * Math.pow(2, failures), MAX_COOLDOWN_SEC);
}

// ── Spawn managed process (type=http) ────────────────────────────────────────
function spawnProcess(cfg) {
  const id  = cfg.id;
  const cwd = expandPath(cfg.cwd || PROJ_ROOT);
  const args = (cfg.args || []).map(expandPath);
  log(`START  ${id}: ${cfg.command} ${args.join(' ')}`);

  const child = spawn(cfg.command, args, {
    cwd,
    stdio: 'inherit',
    shell: false,
    windowsHide: true,
  });

  const entry = processState[id];
  entry.pid       = child.pid;
  entry.startedAt = new Date().toISOString();
  entry.status    = 'starting';

  child.on('exit', (code, signal) => {
    const e = processState[id];
    if (!e) return;
    log(`EXIT   ${id}: code=${code} signal=${signal}`);
    delete childHandles[id];

    const now       = new Date();
    const uptimeSec = e.startedAt ? (now - new Date(e.startedAt)) / 1000 : 0;

    if (uptimeSec < (cfg.minUptimeSec || 10)) {
      e.consecutiveFailures = (e.consecutiveFailures || 0) + 1;
    } else {
      e.consecutiveFailures = 0;
    }
    e.restartCount = (e.restartCount || 0) + 1;
    e.status       = 'stopped';
    e.pid          = null;

    if (e.restartCount >= (cfg.maxRestarts || 10)) {
      log(`DISABLE ${id}: maxRestarts (${cfg.maxRestarts}) reached`);
      e.disabled = true;
      e.status   = 'disabled';
      writeState();
      return;
    }

    const delay = cooldownSec(cfg.backoffBaseSec || 5, e.consecutiveFailures) * 1000;
    const retryAt = new Date(now.getTime() + delay).toISOString();
    e.nextRetryAt = retryAt;
    log(`RETRY  ${id} in ${delay / 1000}s (failures=${e.consecutiveFailures})`);
    writeState();

    setTimeout(() => {
      const curr = processState[id];
      if (!curr || curr.disabled) return;
      childHandles[id] = spawnProcess(cfg);
    }, delay);
  });

  childHandles[id] = child;
  return child;
}

// ── Initialize process state entries ─────────────────────────────────────────
function initProcessState(configs) {
  for (const cfg of configs) {
    if (!processState[cfg.id]) {
      processState[cfg.id] = {
        id:                   cfg.id,
        type:                 cfg.type,
        name:                 cfg.name,
        status:               'unknown',
        pid:                  null,
        startedAt:            null,
        lastCheckedAt:        null,
        restartCount:         0,
        consecutiveFailures:  0,
        nextRetryAt:          null,
        disabled:             false,
      };
    }
  }
}

// ── Check loop (one tick per process) ────────────────────────────────────────
async function checkProcess(cfg) {
  const id    = cfg.id;
  const entry = processState[id];
  if (!entry) return;

  entry.lastCheckedAt = new Date().toISOString();

  // ── session-file type: observe only (no spawn) ──────────────────────────
  if (cfg.type === 'session-file') {
    const sessDir = expandPath(cfg.sessionDir || '');
    try {
      if (!fs.existsSync(sessDir)) { entry.status = 'idle'; entry.activeSession = null; return; }
      const files = fs.readdirSync(sessDir).filter(f => f.endsWith('.json'));
      let running = null;
      let newest  = 0;
      for (const f of files) {
        try {
          const data = JSON.parse(fs.readFileSync(path.join(sessDir, f), 'utf8'));
          if (data.status === 'running') {
            const ts = new Date(data.last_updated || data.start_time || 0).getTime();
            if (ts > newest) { newest = ts; running = data; }
          }
        } catch {}
      }
      if (!running) { entry.status = 'idle'; entry.activeSession = null; return; }

      const staleSec = (Date.now() - newest) / 1000;
      const staleLimit = (cfg.staleMinutes || 15) * 60;
      if (staleSec > staleLimit) {
        entry.status        = 'stale';
        entry.activeSession = { sessionId: running.sessionId, project: running.project, staleSec: Math.floor(staleSec) };
      } else {
        entry.status        = 'running';
        entry.activeSession = { sessionId: running.sessionId, project: running.project, staleSec: Math.floor(staleSec) };
      }
    } catch (e) {
      entry.status = 'unknown';
    }
    return;
  }

  // ── http type: spawn-managed + health check ──────────────────────────────
  if (entry.disabled) return;

  // If process is in cooldown, skip
  if (entry.nextRetryAt && new Date(entry.nextRetryAt) > new Date()) {
    entry.status = 'cooldown';
    return;
  }

  const child = childHandles[id];
  const pidAlive = child ? isPidAlive(child.pid) : false;

  if (!pidAlive && !child) {
    // Not yet started: spawn
    if (entry.restartCount === 0 && entry.status === 'unknown') {
      log(`INIT   ${id}: first start`);
      spawnProcess(cfg);
      entry.status = 'starting';
      return;
    }
    // Stopped without exit handler scheduling retry: restart
    if (entry.status !== 'disabled' && entry.status !== 'cooldown') {
      log(`RESTART ${id}: process gone without scheduled retry`);
      entry.restartCount = (entry.restartCount || 0) + 1;
      if (entry.restartCount >= (cfg.maxRestarts || 10)) {
        log(`DISABLE ${id}: maxRestarts reached`);
        entry.disabled = true; entry.status = 'disabled'; return;
      }
      spawnProcess(cfg);
      entry.status = 'starting';
    }
    return;
  }

  // Process is alive; perform HTTP health check
  if (cfg.healthUrl) {
    const healthy = await checkHttp(cfg.healthUrl);
    if (healthy) {
      entry.status              = 'running';
      entry.consecutiveFailures = 0;
      entry.nextRetryAt         = null;
    } else {
      entry.consecutiveFailures = (entry.consecutiveFailures || 0) + 1;
      entry.status              = 'unhealthy';
      log(`UNHEALTHY ${id}: failures=${entry.consecutiveFailures}`);

      // Kill and let exit handler reschedule restart
      if (child && isPidAlive(child.pid)) {
        try { child.kill('SIGTERM'); } catch {}
      }
    }
  } else {
    entry.status = pidAlive ? 'running' : 'stopped';
  }
}

// ── Main check loop ───────────────────────────────────────────────────────────
async function tick(configs) {
  for (const cfg of configs) {
    try { await checkProcess(cfg); } catch (e) { log(`ERROR check ${cfg.id}: ${e.message}`); }
  }
  writeState();
}

// ── Graceful shutdown ─────────────────────────────────────────────────────────
function shutdown(signal) {
  log(`${signal} received — shutting down`);
  for (const [id, child] of Object.entries(childHandles)) {
    try {
      log(`KILL   ${id} (pid=${child.pid})`);
      child.kill('SIGTERM');
    } catch {}
  }
  for (const entry of Object.values(processState)) {
    entry.status = 'stopped';
  }
  writeState();
  process.exit(0);
}

// ── Entry point ───────────────────────────────────────────────────────────────
function main() {
  log(`ClaudeOS Supervisor starting (pid=${process.pid})`);
  log(`PROJ_ROOT: ${PROJ_ROOT}`);
  log(`STATE_FILE: ${STATE_FILE}`);

  const configs = loadConfig();
  if (configs.length === 0) {
    log('No enabled processes in config/processes.json. Exiting.');
    process.exit(0);
  }
  log(`Loaded ${configs.length} process(es): ${configs.map(c => c.id).join(', ')}`);

  initProcessState(configs);
  writeState();

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT',  () => shutdown('SIGINT'));

  // Start first tick immediately, then loop
  tick(configs);
  setInterval(() => tick(configs), CHECK_INTERVAL_MS);
}

main();
