#!/usr/bin/env node
/**
 * doc-version consistency check
 * Validates that README.md version/agent-count matches CHANGELOG.md + actual agent files.
 * Exit 0 = all OK, Exit 1 = mismatch found.
 */

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
let errors = 0;

function fail(msg) {
  console.error(`::error::${msg}`);
  errors++;
}

function info(msg) {
  console.log(`::notice::${msg}`);
}

// --- 1. CHANGELOG latest version ---
const changelog = fs.readFileSync(path.join(root, 'CHANGELOG.md'), 'utf8');
const changelogMatch = changelog.match(/^## \[?(v[\d.]+)\]?/m);
if (!changelogMatch) {
  fail('CHANGELOG.md: latest version line not found');
  process.exit(1);
}
const latestVersion = changelogMatch[1];
info(`CHANGELOG latest: ${latestVersion}`);

// --- 2. README バージョン行 ---
const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
const readmeVersionMatch = readme.match(/\| バージョン \| \*\*(v[\d.]+)\*\*/);
if (!readmeVersionMatch) {
  fail('README.md: バージョン行が見つかりません');
  process.exit(1);
}
const readmeVersion = readmeVersionMatch[1];
info(`README version: ${readmeVersion}`);

if (readmeVersion !== latestVersion) {
  fail(`バージョンドリフト: README=${readmeVersion} / CHANGELOG=${latestVersion}`);
}

// --- 3. Agent count ---
const agentsDir = path.join(root, '.claude', 'claudeos', 'agents');
const actualAgentCount = fs.readdirSync(agentsDir).filter(f => f.endsWith('.md')).length;
info(`Actual agent count: ${actualAgentCount}`);

const readmeAgentMatch = readme.match(/\| Agents \| \*\*(\d+)体\*\*/);
if (!readmeAgentMatch) {
  fail('README.md: Agents 行が見つかりません');
} else {
  const readmeAgentCount = parseInt(readmeAgentMatch[1], 10);
  info(`README agent count: ${readmeAgentCount}`);
  if (readmeAgentCount !== actualAgentCount) {
    fail(`Agents 数ドリフト: README=${readmeAgentCount}体 / 実ファイル数=${actualAgentCount}体`);
  }
}

// --- 4. Commands count ---
const commandsDir = path.join(root, '.claude', 'claudeos', 'commands');
const actualCommandCount = fs.readdirSync(commandsDir).filter(f => f.endsWith('.md')).length;
info(`Actual command count: ${actualCommandCount}`);

const readmeCommandMatch = readme.match(/(\d+)コマンド/);
if (readmeCommandMatch) {
  const readmeCommandCount = parseInt(readmeCommandMatch[1], 10);
  if (readmeCommandCount !== actualCommandCount) {
    // Warning only — コマンド数は README 内の複数箇所に分散しているため non-blocking
    console.warn(`::warning::Commands 数差異: README=${readmeCommandCount} / 実ファイル数=${actualCommandCount} (非ブロッキング)`);
  }
}

// --- Result ---
if (errors === 0) {
  info(`doc-version check PASSED — README=${readmeVersion}, agents=${actualAgentCount}`);
  process.exit(0);
} else {
  console.error(`doc-version check FAILED: ${errors} error(s)`);
  process.exit(1);
}
