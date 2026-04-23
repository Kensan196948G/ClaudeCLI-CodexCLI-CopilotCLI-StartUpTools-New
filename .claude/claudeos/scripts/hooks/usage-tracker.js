#!/usr/bin/env node
// PostToolUse hook (ClaudeOS v8.2) — P1-7
// Agent ツール呼び出しを検出し、learning.usage_history.agents に使用実績を記録する。
// settings.json の PostToolUse で matcher: "Agent" として登録する。

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
  const tmp = `${file}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + "\n", "utf8");
  fs.renameSync(tmp, file);
}

// Claude Code は PostToolUse hook 起動時に stdin から tool 情報を JSON で渡す
let input = "";
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  try {
    const hookData = JSON.parse(input);
    const toolName  = hookData.tool_name || hookData.tool || "";
    const toolInput = hookData.tool_input || hookData.input || {};

    // Agent ツール以外はスキップ
    if (!toolName.toLowerCase().includes("agent")) {
      process.exit(0);
    }

    // subagent_type や description からエージェントロール名を推定
    const subagentType = toolInput.subagent_type || "general-purpose";
    const description  = (toolInput.description || "").slice(0, 80);
    const agentKey     = subagentType.replace(/[^a-zA-Z0-9_-]/g, "_");

    const state = readJson(STATE_FILE);
    if (!state) { process.exit(0); }

    state.learning = state.learning || {};
    state.learning.usage_history = state.learning.usage_history || {};
    state.learning.usage_history.agents = state.learning.usage_history.agents || {};

    const agents = state.learning.usage_history.agents;
    const now = new Date().toISOString();

    if (!agents[agentKey]) {
      agents[agentKey] = { call_count: 0, last_used: null, last_description: "" };
    }
    agents[agentKey].call_count += 1;
    agents[agentKey].last_used = now;
    if (description) agents[agentKey].last_description = description;

    // セッション全体のカウンターも更新
    agents._total_agent_calls = (agents._total_agent_calls || 0) + 1;
    agents._last_agent_call_at = now;

    writeJsonAtomic(STATE_FILE, state);
    console.log(`[UsageTracker] agent=${agentKey} total_calls=${agents[agentKey].call_count}`);
  } catch (err) {
    // hook 失敗はサイレント（tool 実行をブロックしない）
    console.error(`[UsageTracker] error: ${err.message}`);
  }
  process.exit(0);
});

// stdin が pipe されていない場合（直接実行）は即時終了
if (process.stdin.isTTY) {
  process.exit(0);
}
