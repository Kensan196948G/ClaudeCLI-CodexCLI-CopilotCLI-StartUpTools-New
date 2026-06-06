// ============================================================================
// Generate-and-filter — 汎用 dynamic workflow テンプレ (ClaudeOS v9.0+)
// ----------------------------------------------------------------------------
// パターン: 候補を「網羅的に」大量生成し、独立した評価 agent でふるい落とす。
//   - agentic laziness 対策: 生成 agent を複数観点で並列展開し打ち切りを防ぐ
//   - self-preferential bias 対策: 生成と評価を別 agent に分離し、keep=false 既定で
//     「採用する根拠が無ければ落とす」厳格フィルタにする
// 用途例: テストケース網羅 / 改善案ブレスト / エッジケース洗い出し / 候補 API 設計
//
// 使い方: /generate-and-filter  (args で対象と基準を渡す)
//   args.target   … 何を生成するか（例: "決済モジュールのエッジケーステスト"）
//   args.criteria … 採用基準（例: "実際に発生しうる / 既存テスト未カバー"）
//   args.count    … 生成 agent 数（既定 4。観点を分けて並列生成する）
// ============================================================================

export const meta = {
  name: "generate-and-filter",
  description: "候補を多観点で大量生成し、独立評価 agent が keep=false 既定で厳格にふるい落とす汎用テンプレ",
  phases: [
    { title: "Generate", detail: "複数 agent が観点別に候補を網羅生成" },
    { title: "Filter",   detail: "独立 agent が各候補を評価 (keep=false 既定)" },
    { title: "Report",   detail: "採用候補を統合して報告" },
  ],
};

// 生成 agent が返す候補集合
const CANDIDATE_SCHEMA = {
  type: "object",
  required: ["candidates"],
  properties: {
    candidates: {
      type: "array",
      items: {
        type: "object",
        required: ["title", "description"],
        properties: {
          title:       { type: "string" },
          description: { type: "string" },
          rationale:   { type: "string" },
        },
      },
    },
  },
};

// 評価 agent が返す採否判定 (keep を既定 false にして self-preferential bias を抑制)
const FILTER_SCHEMA = {
  type: "object",
  required: ["keep", "score", "reasoning"],
  properties: {
    keep:      { type: "boolean" },                          // 既定 false: 採用は根拠必須
    score:     { type: "number", minimum: 0, maximum: 1 },
    reasoning: { type: "string" },
  },
};

const target   = args?.target   || "生成対象を args.target に渡してください";
const criteria = args?.criteria || "現実的に発生しうる / 既存で未カバー / 価値が高い";
const count    = Math.max(1, Math.min(8, args?.count || 4));  // 1〜8 観点に制限

log(`🧪 Generate-and-filter 開始: "${target}" (生成 ${count} 観点 / 基準: ${criteria})`);

// --- Generate: 観点をずらした複数 agent で網羅生成 (打ち切り＝laziness を防ぐ) ---
phase("Generate");
const generated = await parallel(
  Array.from({ length: count }, (_, i) => () => agent(
    `生成対象: "${target}"\n\n` +
    `あなたは生成 agent #${i + 1} です。他の生成 agent とは異なる切り口で、` +
    `候補をできるだけ網羅的に洗い出してください（最低 5 件）。\n` +
    `「だいたいで十分」と早期に打ち切らず、見落としがちな候補まで挙げてください。\n` +
    `各候補は title / description / rationale を含めてください。`,
    { label: `gen:#${i + 1}`, phase: "Generate", schema: CANDIDATE_SCHEMA }
  ))
);

// 全候補を平坦化し、title で素朴に重複除去
const pool = generated
  .filter(Boolean)
  .flatMap(g => g.candidates || []);
const seen = new Set();
const unique = pool.filter(c => {
  const key = (c.title || "").trim().toLowerCase();
  if (!key || seen.has(key)) return false;
  seen.add(key);
  return true;
});

log(`📋 生成 ${pool.length} 件 → 重複除去後 ${unique.length} 件 → フィルタへ`);

if (unique.length === 0) {
  log("⚠️ 候補が生成されませんでした。args.target を見直してください。");
  return { kept: [], rejected: [], total_generated: 0 };
}

// --- Filter: 候補ごとに独立 agent で評価 (生成元とは別 agent = bias 排除) ---
phase("Filter");
const judged = await pipeline(
  unique,
  c => agent(
    `次の候補を採用基準に照らして厳格に評価してください。\n\n` +
    `候補: ${c.title}\n説明: ${c.description}\n` +
    `${c.rationale ? `生成根拠: ${c.rationale}\n` : ""}` +
    `\n採用基準: ${criteria}\n\n` +
    `デフォルトは keep=false です。基準を明確に満たす根拠を示せる場合のみ keep=true に` +
    `してください。score は採用度合い (0〜1)、reasoning に判断理由を日本語で書いてください。`,
    { label: `filter:${(c.title || "").slice(0, 24)}`, phase: "Filter", schema: FILTER_SCHEMA }
  ).then(v => ({ candidate: c, verdict: v }))
);

const valid    = judged.filter(j => j && j.verdict);
const kept     = valid.filter(j => j.verdict.keep).sort((a, b) => b.verdict.score - a.verdict.score);
const rejected = valid.filter(j => !j.verdict.keep);

log(`✅ 採用 ${kept.length} 件 / ❌ 不採用 ${rejected.length} 件`);

// --- Report: 採用候補を統合して最終報告 ---
phase("Report");
const report = await agent(
  `生成対象 "${target}" について、フィルタを通過した候補を整理して報告してください。\n\n` +
  `採用候補 (${kept.length}件、score 降順):\n` +
  kept.map((j, i) => `${i + 1}. [${j.verdict.score.toFixed(2)}] ${j.candidate.title} — ${j.candidate.description}`).join("\n") +
  `\n\n以下を日本語でまとめてください:\n` +
  `1. 採用候補の要約と優先順位\n` +
  `2. 次に取るべきアクション（実装 / Issue 化 / テスト追加など）\n` +
  `3. 不採用が多かった観点があれば、その傾向`,
  { label: "report:synthesize", phase: "Report" }
);

return {
  target,
  total_generated: pool.length,
  kept: kept.map(j => ({ ...j.candidate, score: j.verdict.score, reasoning: j.verdict.reasoning })),
  rejected_count: rejected.length,
  report,
};
