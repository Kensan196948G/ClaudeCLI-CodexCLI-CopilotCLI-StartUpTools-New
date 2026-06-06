// rule-distillation — セッション/レビュー/履歴から運用ルールを蒸留 (提案のみ)
// ---------------------------------------------------------------------------
// 出典: dynamic workflows "Memory & Rule Adherence" パターン
//   (Thariq Shihipar & Sid Bidasaria, 2026-06-02)
//
// 用途: reasoning-bank・git 履歴・CodeRabbit/Codex 指摘・MEMORY.md を横断マイニングし、
//       繰り返し現れる是正をクラスタ化→反証検証→生き残りを CLAUDE.md/MEMORY.md 追記案へ蒸留。
//       ClaudeOS の EvolutionManager / self-evolution を支援する。
//
// 重要: CLAUDE.md §18 (CLAUDE.md/settings.json/hooks の自己書換禁止) を尊重し、
//       本 workflow は **常に提案のみ** (ファイルは編集しない)。採用は人間が判断する。
//
// 使い方:
//   /rule-distillation
//   args 例: { "lookback": 50, "target": "MEMORY.md" }
//     lookback: 走査する直近 git コミット数 (既定 40)
//     target  : 蒸留先の想定 ("MEMORY.md" | "CLAUDE.md")。既定 "MEMORY.md"
// ---------------------------------------------------------------------------

export const meta = {
  name: "rule-distillation",
  description: "セッション/レビュー/履歴から繰り返しの是正を蒸留し運用ルール追記案を生成 (提案のみ・自動適用なし)",
  phases: [
    { title: "Mine",     detail: "複数ソースを並列マイニングし候補ルールを抽出" },
    { title: "Cluster",  detail: "候補を統合・重複排除" },
    { title: "Verify",   detail: "各候補を adversarial 検証 (実在性・既出チェック)" },
    { title: "Distill",  detail: "生存候補を追記案へ蒸留" },
  ],
};

const MINE_SCHEMA = {
  type: "object",
  required: ["source", "candidates"],
  properties: {
    source: { type: "string" },
    candidates: {
      type: "array",
      items: {
        type: "object",
        required: ["rule", "evidence", "frequency"],
        properties: {
          rule:      { type: "string" },   // 「〜すべき/〜してはいけない」形の運用ルール
          evidence:  { type: "string" },   // 根拠 (コミット/指摘/パターンの引用)
          frequency: { type: "number" },   // 観測回数の目安
        },
      },
    },
  },
};

const VERIFY_SCHEMA = {
  type: "object",
  required: ["rule", "is_real", "already_documented", "recommendation", "reasoning"],
  properties: {
    rule:               { type: "string" },
    is_real:            { type: "boolean" },  // 本当に繰り返す是正か (一度きりの偶発でない)
    already_documented: { type: "boolean" },  // 既に CLAUDE.md/MEMORY.md にあるか
    recommendation:     { type: "string", enum: ["adopt", "merge", "drop"] },
    reasoning:          { type: "string" },
  },
};

// args が JSON 文字列で届くケース(自然言語起動など)に備え正規化
const A = typeof args === "string" ? (() => { try { return JSON.parse(args) || {}; } catch { return {}; } })() : (args || {});

const lookback = Math.max(5, Number(A.lookback) || 40);
const target   = A.target === "CLAUDE.md" ? "CLAUDE.md" : "MEMORY.md";

log(`🧬 rule-distillation — 提案のみ (自動適用なし) / target=${target} / lookback=${lookback}コミット`);
if (budget?.total) log(`📊 token 予算: 残 ${Math.round(budget.remaining() / 1000)}k`);

// --- Phase 1: Mine (ソース別並列) ------------------------------------------

const SOURCES = [
  {
    key: "reasoning-bank",
    prompt: `.claude/claudeos/data/reasoning-bank.json を読み、success_patterns / failure_patterns から ` +
            `「今後こうすべき」という運用ルール候補を抽出してください。各候補に根拠と観測頻度を付ける。`,
  },
  {
    key: "git-history",
    prompt: `直近 ${lookback} コミット (git log -n ${lookback} --format=...) を確認し、` +
            `「同種の修正が繰り返されている」パターン (例: 同じ種類の lint 修正・docs ドリフト修正・命名是正) を` +
            `運用ルール候補として抽出してください。fix/revert が多いテーマは是正ルールの種。`,
  },
  {
    key: "review-comments",
    prompt: `CodeRabbit / Codex のレビュー指摘の痕跡 (reports/・PR コメント・コミットの "CodeRabbit"/"Codex" 言及) を` +
            `gh / Grep で確認し、繰り返し指摘される観点を運用ルール候補として抽出してください。`,
  },
  {
    key: "existing-memory",
    prompt: `既存の MEMORY.md (memory ディレクトリ) と CLAUDE.md の feedback/禁止事項を読み、` +
            `「既に明文化されている運用ルール」を列挙してください (後段の既出チェックの基準にする)。` +
            `これらは新規候補ではなく "既出リスト" として rule に記し frequency は 0 とする。`,
  },
];

phase("Mine");
const mined = await parallel(
  SOURCES.map(s => () => agent(s.prompt, { label: `mine:${s.key}`, phase: "Mine", schema: MINE_SCHEMA }))
);
const allCandidates = mined.filter(Boolean).flatMap(m => (m.candidates || []).map(c => ({ ...c, source: m.source })));
log(`📋 候補 ${allCandidates.length} 件 (既出リスト含む) → クラスタリングへ`);

if (allCandidates.length === 0) {
  log("✅ 抽出候補なし");
  return { target, proposals: "抽出された候補ルールはありませんでした。", candidates: [] };
}

// --- Phase 2: Cluster (統合・重複排除) -------------------------------------

phase("Cluster");
const CLUSTER_SCHEMA = {
  type: "object",
  required: ["clusters"],
  properties: {
    clusters: {
      type: "array",
      items: {
        type: "object",
        required: ["rule", "evidence", "frequency"],
        properties: {
          rule:      { type: "string" },
          evidence:  { type: "string" },
          frequency: { type: "number" },
        },
      },
    },
  },
};
const clustered = await agent(
  `以下の候補ルール群を意味の近いもので統合・重複排除してください。\n\n` +
  `${JSON.stringify(allCandidates, null, 2)}\n\n` +
  `同義のルールは1件に統合し evidence をまとめ frequency を合算。` +
  `source=existing-memory 由来の "既出" は統合先の判断材料に使うが、それ自体は新規 cluster にしない。` +
  `新規性のある運用ルールのみ clusters に残す。`,
  { label: "cluster", phase: "Cluster", schema: CLUSTER_SCHEMA }
);
const clusters = (clustered?.clusters || []).filter(c => c && c.rule);
log(`🔗 クラスタ ${clusters.length} 件 → adversarial 検証へ`);

// --- Phase 3: Verify (候補ごと adversarial) --------------------------------

phase("Verify");
const verified = await pipeline(
  clusters,
  (c) => agent(
    `次の運用ルール候補を adversarial に検証してください。\n\n` +
    `候補: ${c.rule}\n根拠: ${c.evidence}\n観測頻度: ${c.frequency}\n\n` +
    `判定:\n` +
    `- is_real: 一度きりの偶発でなく「繰り返す是正」か (疑わしければ false)\n` +
    `- already_documented: CLAUDE.md / MEMORY.md に既に同趣旨があるか (実際に Grep して確認)\n` +
    `- recommendation: adopt(新規採用) / merge(既存へ統合) / drop(不採用)\n` +
    `デフォルトは保守的に。曖昧なら drop。`,
    { label: `verify:${c.rule.slice(0, 24)}`, phase: "Verify", schema: VERIFY_SCHEMA }
  ).then(v => v ? { ...c, ...v } : null)
);
const survivors = verified.filter(Boolean).filter(v => v.is_real && v.recommendation !== "drop");
log(`🎯 生存候補 ${survivors.length} 件 (adopt/merge) → 蒸留へ`);

// --- Phase 4: Distill (追記案生成・提案のみ) -------------------------------

phase("Distill");
const proposals = await agent(
  `以下の生存ルールを ${target} への追記案として日本語で蒸留してください。**提案のみ。ファイルは編集しないこと。**\n\n` +
  `${JSON.stringify(survivors, null, 2)}\n\n` +
  (target === "MEMORY.md"
    ? `各ルールを memory ファイル形式 (frontmatter: name/description/metadata.type=feedback, 本文に Why/How to apply) の追記案として提示。`
    : `各ルールを CLAUDE.md の適切な節 (例: 禁止事項 / 行動原則) への追記案として提示。§18 により自動適用はせず人間レビュー前提と明記。`) +
  `\n各案に「採用/統合(merge 先)/見送り」の推奨と理由を添える。`,
  { label: "distill", phase: "Distill" }
);

return {
  target,
  counts: { mined: allCandidates.length, clustered: clusters.length, survivors: survivors.length },
  survivors,
  proposals,
  note: "提案のみ。CLAUDE.md/MEMORY.md への反映は人間が判断する (§18)。",
};
