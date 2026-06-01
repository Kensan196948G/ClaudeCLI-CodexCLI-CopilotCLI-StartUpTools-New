export const meta = {
  name: "bug-investigation",
  description: "バグを複数の競合仮説で並列調査し、議論・反証を経て根本原因を特定",
  phases: [
    { title: "Hypothesize", detail: "5エージェントが独立した仮説を立案" },
    { title: "Debate",      detail: "各エージェントが他の仮説を反証" },
    { title: "Converge",    detail: "生き残った仮説から根本原因を特定" },
  ],
};

const HYPOTHESIS_SCHEMA = {
  type: "object",
  required: ["hypothesis", "evidence", "investigation_steps", "confidence"],
  properties: {
    hypothesis:          { type: "string" },
    evidence:            { type: "array", items: { type: "string" } },
    investigation_steps: { type: "array", items: { type: "string" } },
    confidence:          { type: "number", minimum: 0, maximum: 1 },
  },
};

const DEBATE_SCHEMA = {
  type: "object",
  required: ["target_hypothesis", "refutation", "survives", "confidence_after"],
  properties: {
    target_hypothesis: { type: "string" },
    refutation:        { type: "string" },
    survives:          { type: "boolean" },
    confidence_after:  { type: "number", minimum: 0, maximum: 1 },
  },
};

const bugDescription = args?.bug || "バグの症状を args.bug に渡してください";

log(`🐛 調査対象: ${bugDescription}`);

phase("Hypothesize");
const hypotheses = await parallel([
  () => agent(
    `バグ: "${bugDescription}"\n仮説1: ネットワーク/API 通信の問題（タイムアウト・レスポンス形式・認証）の観点で調査し、原因仮説を立ててください。コードを実際に確認してください。`,
    { label: "hyp:network", phase: "Hypothesize", schema: HYPOTHESIS_SCHEMA }
  ),
  () => agent(
    `バグ: "${bugDescription}"\n仮説2: 状態管理・データフローの問題（変数の初期化・非同期処理・競合状態）の観点で調査し、原因仮説を立ててください。コードを実際に確認してください。`,
    { label: "hyp:state", phase: "Hypothesize", schema: HYPOTHESIS_SCHEMA }
  ),
  () => agent(
    `バグ: "${bugDescription}"\n仮説3: 入力バリデーション・型変換の問題（null チェック漏れ・型不一致・エッジケース）の観点で調査し、原因仮説を立ててください。コードを実際に確認してください。`,
    { label: "hyp:validation", phase: "Hypothesize", schema: HYPOTHESIS_SCHEMA }
  ),
  () => agent(
    `バグ: "${bugDescription}"\n仮説4: 外部依存（ライブラリのバージョン・環境設定・DB状態）の問題の観点で調査し、原因仮説を立ててください。コードを実際に確認してください。`,
    { label: "hyp:deps", phase: "Hypothesize", schema: HYPOTHESIS_SCHEMA }
  ),
  () => agent(
    `バグ: "${bugDescription}"\n仮説5: ロジックエラー（条件式の誤り・境界値・off-by-one）の観点で調査し、原因仮説を立ててください。コードを実際に確認してください。`,
    { label: "hyp:logic", phase: "Hypothesize", schema: HYPOTHESIS_SCHEMA }
  ),
]);

const validHyps = hypotheses.filter(Boolean);
log(`📋 仮説 ${validHyps.length} 件 → 相互反証へ`);

phase("Debate");
const debateResults = await pipeline(
  validHyps,
  h => agent(
    `以下の仮説を科学的に反証してください。他の仮説と比較し、この仮説が正しくない理由を探してください。\n\n` +
    `仮説: ${h.hypothesis}\n` +
    `根拠: ${(h.evidence || []).join(", ")}\n\n` +
    `全仮説:\n${validHyps.map((v, i) => `${i+1}. ${v.hypothesis}`).join("\n")}\n\n` +
    `この仮説の弱点・反証を詳細に示してください。デフォルトは survives=false（反証できたら false）。`,
    { label: `debate:${h.hypothesis.slice(0, 30)}`, phase: "Debate", schema: DEBATE_SCHEMA }
  )
);

const survivors = debateResults
  .filter(Boolean)
  .filter(d => d.survives)
  .map(d => ({ ...validHyps.find(h => h.hypothesis === d.target_hypothesis || d.target_hypothesis?.includes(h.hypothesis?.slice(0,20))), ...d }));

log(`🎯 生き残った仮説: ${survivors.length} 件`);

phase("Converge");
const conclusion = await agent(
  `バグ "${bugDescription}" について、競合仮説の議論・反証を経た結果を分析してください。\n\n` +
  `生き残った仮説 (${survivors.length}件):\n${JSON.stringify(survivors, null, 2)}\n\n` +
  `全仮説とデバート結果:\n${JSON.stringify(debateResults.filter(Boolean), null, 2)}\n\n` +
  `以下を日本語で出力してください:\n` +
  `1. 根本原因（最も可能性が高い仮説とその理由）\n` +
  `2. 修正方針（具体的なコード変更箇所と方法）\n` +
  `3. 検証方法（修正が正しいことを確認するテスト）\n` +
  `4. 再発防止策`,
  { label: "converge:conclusion", phase: "Converge" }
);

return { survivors, conclusion };
