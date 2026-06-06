// ============================================================================
// Loop-until-done — 汎用 dynamic workflow テンプレ (ClaudeOS v9.0+)
// ----------------------------------------------------------------------------
// パターン: 明示的な終了条件を満たすまで script の while で反復継続する。
//   - agentic laziness 対策の中核: 「だいたい終わった」での早期打ち切りを構造的に封じる。
//     完了判定は作業 agent 自身ではなく独立した checker agent が done=false 既定で下す。
//   - 暴走防止: maxRounds で必ず上限を設ける（ClaudeOS「止まらない。ただし暴走しない」）。
// 用途例: 残課題ゼロ化 / lint warning 全消し / TODO 全回収 / カバレッジ目標到達
//
// 使い方: /loop-until-done  (args で目的と上限を渡す)
//   args.objective … 達成したいこと（例: "src/ 配下の TODO コメントを全て解消"）
//   args.doneWhen  … 完了条件の文言（例: "未解決 TODO が 0 件"）
//   args.maxRounds … 反復上限（既定 5。暴走防止のハードリミット）
// ============================================================================

export const meta = {
  name: "loop-until-done",
  description: "終了条件を満たすまで作業→独立 checker (done=false 既定) を反復。maxRounds で暴走を防ぐ汎用テンプレ",
  phases: [
    { title: "Loop", detail: "作業 agent → checker agent を完了まで反復" },
    { title: "Wrap", detail: "全ラウンドの成果を統合して報告" },
  ],
};

// checker agent が返す完了判定 (done を既定 false にして早期終了を抑制)
const CHECK_SCHEMA = {
  type: "object",
  required: ["done", "remaining", "progress_note"],
  properties: {
    done:          { type: "boolean" },                      // 既定 false: 完了は根拠必須
    remaining:     { type: "array", items: { type: "string" } },
    progress_note: { type: "string" },
  },
};

const objective = args?.objective || "達成目的を args.objective に渡してください";
const doneWhen  = args?.doneWhen  || "残作業が 0 件になったとき";
const maxRounds = Math.max(1, Math.min(12, args?.maxRounds || 5));  // 1〜12 に制限

log(`🔁 Loop-until-done 開始: "${objective}" / 完了条件: ${doneWhen} / 上限 ${maxRounds} ラウンド`);

phase("Loop");
const history = [];
let done = false;
let lastRemaining = [];
let round = 0;

while (!done && round < maxRounds) {
  round += 1;

  // --- 作業 agent: 1 ラウンド分の前進を行う ---
  const focus = lastRemaining.length
    ? `前ラウンドで残った項目に集中してください:\n${lastRemaining.map((r, i) => `${i + 1}. ${r}`).join("\n")}`
    : "まず現状を調査し、着手すべき項目を洗い出してから作業を進めてください。";

  const work = await agent(
    `目的: "${objective}"\n\n` +
    `これはラウンド ${round}/${maxRounds} です。${focus}\n\n` +
    `このラウンドで可能な限り前進させてください。「だいたいで十分」と早期に切り上げず、` +
    `着実に項目を片付けてください。完了できなかった項目は明示してください。`,
    { label: `work:round-${round}`, phase: "Loop" }
  );

  // --- checker agent: 作業 agent とは独立に完了を判定 (self-preferential bias 排除) ---
  const check = await agent(
    `目的: "${objective}"\n完了条件: ${doneWhen}\n\n` +
    `ラウンド ${round} の作業結果:\n${work}\n\n` +
    `あなたは独立した検証者です。実際に現状を確認し、完了条件を満たしているか判定してください。\n` +
    `デフォルトは done=false です。完了条件を確実に満たす根拠を確認できた場合のみ done=true に` +
    `してください。未達なら remaining に残項目を、progress_note に進捗評価を日本語で書いてください。`,
    { label: `check:round-${round}`, phase: "Loop", schema: CHECK_SCHEMA }
  );

  history.push({ round, work_summary: work, check });

  if (check) {
    done = check.done === true;
    lastRemaining = check.remaining || [];
    log(`  ↳ ラウンド ${round}: done=${done} / 残 ${lastRemaining.length} 件 — ${check.progress_note || ""}`);
  } else {
    // checker が応答しなかった場合は安全側に倒し、次ラウンドへ
    log(`  ↳ ラウンド ${round}: checker 応答なし → 継続`);
  }
}

if (done) {
  log(`✅ 完了条件を満たしました (${round} ラウンド)`);
} else {
  log(`⏱ 上限 ${maxRounds} ラウンド到達。未完のまま終了 (残 ${lastRemaining.length} 件)。Issue 化を検討してください。`);
}

// --- Wrap: 全ラウンドの成果を統合報告 ---
phase("Wrap");
const summary = await agent(
  `目的 "${objective}" について、${round} ラウンドの作業を統合して報告してください。\n\n` +
  `完了状態: ${done ? "達成" : `未達 (上限到達、残 ${lastRemaining.length} 件)`}\n` +
  `各ラウンドの判定:\n` +
  history.map(h => `- R${h.round}: done=${h.check?.done} / ${h.check?.progress_note || "(判定なし)"}`).join("\n") +
  `\n\n以下を日本語でまとめてください:\n` +
  `1. 達成できたこと\n` +
  `2. 未達なら残課題と、次セッションでの再開ポイント（Issue 化候補）\n` +
  `3. このタスクで詰まった原因があれば`,
  { label: "wrap:summary", phase: "Wrap" }
);

return {
  objective,
  done,
  rounds: round,
  remaining: lastRemaining,
  summary,
};
