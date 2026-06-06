// issue-triage — GitHub Issue を大規模分類・重複除去・アクション提案
// ---------------------------------------------------------------------------
// 出典: dynamic workflows "Triage at Scale" パターン
//   (Thariq Shihipar & Sid Bidasaria, 2026-06-02)
//
// 用途: open Issue を分類 (P1/P2/P3・カテゴリ)、既存との重複を検出、
//       ラベル付け/重複クローズ/エスカレーションのアクションを提案する。
//       ClaudeOS の Issue Factory / Agent Communication Protocol を補完。
//
// 安全既定: apply=false (提案のみ。Issue は変更しない)。
//           apply=true でラベル付けのみ実行 (クローズは安全のため常に提案止まり)。
//
// 使い方:
//   /issue-triage
//   args 例: { "limit": 50, "batchSize": 8, "apply": false }
// ---------------------------------------------------------------------------

export const meta = {
  name: "issue-triage",
  description: "open GitHub Issue を分類・重複除去・アクション提案 (既定 dry-run・apply でラベル付けのみ実行)",
  phases: [
    { title: "Fetch",      detail: "open Issue を取得" },
    { title: "Classify",   detail: "バッチ単位で優先度・カテゴリ・重複候補を分類" },
    { title: "Synthesize", detail: "重複統合 + アクション計画レポート" },
  ],
};

const FETCH_SCHEMA = {
  type: "object",
  required: ["issues", "total"],
  properties: {
    total: { type: "number" },
    issues: {
      type: "array",
      items: {
        type: "object",
        required: ["number", "title"],
        properties: {
          number:       { type: "number" },
          title:        { type: "string" },
          labels:       { type: "array", items: { type: "string" } },
          created:      { type: "string" },
          body_excerpt: { type: "string" },
        },
      },
    },
  },
};

const CLASSIFY_SCHEMA = {
  type: "object",
  required: ["results"],
  properties: {
    results: {
      type: "array",
      items: {
        type: "object",
        required: ["number", "priority", "category", "suggested_labels", "action", "reasoning"],
        properties: {
          number:               { type: "number" },
          priority:             { type: "string", enum: ["P1", "P2", "P3"] },
          category:             { type: "string" },   // ci/security/quality/ux/docs/infra 等
          suggested_labels:     { type: "array", items: { type: "string" } },
          possible_duplicate_of:{ type: "number" },    // 重複候補の Issue 番号 (無ければ 0)
          action:               { type: "string", enum: ["triage", "close-dup", "escalate", "needs-info"] },
          reasoning:            { type: "string" },
        },
      },
    },
  },
};

// args が JSON 文字列で届くケース(自然言語起動など)に備え正規化
const A = typeof args === "string" ? (() => { try { return JSON.parse(args) || {}; } catch { return {}; } })() : (args || {});

const limit     = Math.max(1, Number(A.limit) || 50);
const batchSize  = Math.max(1, Number(A.batchSize) || 8);
const apply     = A.apply === true;

log(`📋 issue-triage — ${apply ? "⚡ APPLY (ラベル付けのみ)" : "🔍 DRY-RUN (提案のみ)"} / limit=${limit}`);
if (budget?.total) log(`📊 token 予算: 残 ${Math.round(budget.remaining() / 1000)}k`);

// --- Phase 1: Fetch --------------------------------------------------------

phase("Fetch");
const fetched = await agent(
  `gh issue list --state open --limit ${limit} --json number,title,labels,createdAt,body を実行し、` +
  `open Issue を取得して構造化してください。body_excerpt は先頭 200 字程度に要約。` +
  `agent-msg 等の運用メッセージ Issue も含めて全件返す。total も返す。`,
  { label: "fetch", phase: "Fetch", schema: FETCH_SCHEMA }
);
const issues = (fetched?.issues || []).filter(i => i && typeof i.number === "number");
log(`📥 open Issue ${issues.length} 件取得`);

if (issues.length === 0) {
  log("✅ open Issue なし — triage 不要");
  return { total: 0, classified: [], report: "open Issue はありませんでした。" };
}

// --- Phase 2: Classify (バッチ並列) ----------------------------------------

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}
const batches = chunk(issues, batchSize);

phase("Classify");
log(`🔁 ${batches.length} バッチで分類 (全 Issue リストを各バッチへ渡し重複検出を可能にする)`);

const allTitles = issues.map(i => `#${i.number} ${i.title}`).join("\n");
const classifiedOut = await pipeline(
  batches,
  (batch, _o, idx) => agent(
    `以下の Issue バッチを分類してください。\n\n` +
    `【分類対象 (${batch.length}件)】\n${JSON.stringify(batch, null, 2)}\n\n` +
    `【全 open Issue 一覧 (重複候補判定用)】\n${allTitles}\n\n` +
    `各 Issue に対し:\n` +
    `- priority: P1(CI/セキュリティ/データ影響) / P2(品質/UX/テスト) / P3(軽微)\n` +
    `- category: ci/security/quality/ux/docs/infra/agent-msg 等\n` +
    `- suggested_labels: 付与推奨ラベル\n` +
    `- possible_duplicate_of: 重複と思われる別 Issue 番号 (無ければ 0)\n` +
    `- action: triage(通常) / close-dup(重複) / escalate(緊急) / needs-info(情報不足)\n` +
    `必要なら gh issue view で本文を確認すること。`,
    { label: `classify:batch${idx + 1}/${batches.length}`, phase: "Classify", schema: CLASSIFY_SCHEMA }
  ).then(r => (r?.results || []))
);
const classified = classifiedOut.filter(Boolean).flat();

const byPrio = { P1: [], P2: [], P3: [] };
for (const c of classified) (byPrio[c.priority] || byPrio.P3).push(c);
const dups = classified.filter(c => c.possible_duplicate_of && c.possible_duplicate_of > 0);
log(`📊 分類: P1=${byPrio.P1.length} P2=${byPrio.P2.length} P3=${byPrio.P3.length} / 重複候補 ${dups.length} 件`);

// --- Phase 2b: ラベル付け (apply 時のみ) -----------------------------------

let labelResult = { applied: 0, note: "apply=false のためラベル付けなし" };
if (apply) {
  const withLabels = classified.filter(c => (c.suggested_labels || []).length > 0);
  const labeled = await pipeline(
    withLabels,
    (c) => agent(
      `Issue #${c.number} に対し、既存ラベルと矛盾しない範囲で次のラベルを ` +
      `gh issue edit ${c.number} --add-label でラベル付けしてください: ${c.suggested_labels.join(", ")}\n` +
      `存在しないラベルは作らず skip。結果を "added: <labels>" か "skipped: <reason>" で1行返す。` +
      `クローズや本文編集は行わないこと。`,
      { label: `label:#${c.number}`, phase: "Classify" }
    )
  );
  labelResult = { applied: labeled.filter(Boolean).length, note: "ラベル付けのみ実行 (クローズは提案止まり)" };
  log(`🏷 ラベル付け ${labelResult.applied} 件`);
}

// --- Phase 3: Synthesize ---------------------------------------------------

phase("Synthesize");
const report = await agent(
  `Issue triage 結果を日本語レポートにまとめてください。\n\n` +
  `総数 ${issues.length} / P1=${byPrio.P1.length} P2=${byPrio.P2.length} P3=${byPrio.P3.length} / 重複候補 ${dups.length}\n` +
  `モード: ${apply ? "APPLY (ラベル付け済)" : "DRY-RUN (提案のみ)"}\n\n` +
  `分類結果:\n${JSON.stringify(classified, null, 2)}\n\n` +
  `レポート構成: ## Triage サマリー / ### 🔴 P1 (即対応) / ### 🟡 P2 / ### ⚪ P3 / ` +
  `### 重複候補 (close-dup 提案) / ### 情報不足 (needs-info) / ### 次アクション。` +
  `重複候補は「#X は #Y の重複」の形で明示し、クローズは提案として記載 (自動クローズしない)。`,
  { label: "synthesize", phase: "Synthesize" }
);

return {
  total: issues.length,
  apply,
  counts: { P1: byPrio.P1.length, P2: byPrio.P2.length, P3: byPrio.P3.length, duplicates: dups.length },
  labelResult,
  classified,
  report,
};
