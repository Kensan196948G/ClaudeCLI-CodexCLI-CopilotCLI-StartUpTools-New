// ============================================================================
// Classify-and-act — 汎用 dynamic workflow テンプレ (ClaudeOS v9.0+)
// ----------------------------------------------------------------------------
// パターン: 入力群をまず分類し、種別ごとに最適なハンドラ agent へ分岐実行する。
//   - goal drift 対策: 各 item に「目的＋種別」を毎回再注入して処理するため、
//     大量処理でも当初の目的から逸れない。
//   - 効率化: 全 item を 1 つの巨大プロンプトに詰めず、item 単位で並列分散する。
// 用途例: Issue トリアージ (bug/feature/question 分岐) / ログ分類 / PR レビュー振り分け
//
// 使い方: /classify-and-act  (args で対象と分類軸を渡す)
//   args.items      … 処理対象の配列（文字列 or {id,text}）。例: Issue タイトル一覧
//   args.categories … 分類カテゴリの配列。例: ["bug","feature","question","docs"]
//   args.goal       … 全体目的（例: "未トリアージ Issue を分類しラベル方針を決める"）
// ============================================================================

export const meta = {
  name: "classify-and-act",
  description: "入力群を分類し、種別ごとにハンドラ agent へ分岐実行。各 item へ目的を再注入し goal drift を防ぐ汎用テンプレ",
  phases: [
    { title: "Classify", detail: "全 item を許可カテゴリのいずれかへ分類" },
    { title: "Act",      detail: "種別ごとのハンドラ agent が並列処理" },
    { title: "Summarize", detail: "分類分布と対応方針を統合報告" },
  ],
};

// 分類 agent が返す各 item の判定 (category は許可リストに制約)
const buildClassifySchema = (categories) => ({
  type: "object",
  required: ["classifications"],
  properties: {
    classifications: {
      type: "array",
      items: {
        type: "object",
        required: ["item", "category", "confidence"],
        properties: {
          item:       { type: "string" },
          category:   { type: "string", enum: categories },   // 許可カテゴリ外を弾く
          confidence: { type: "number", minimum: 0, maximum: 1 },
          reason:     { type: "string" },
        },
      },
    },
  },
});

const rawItems   = Array.isArray(args?.items) ? args.items : [];
const categories = Array.isArray(args?.categories) && args.categories.length
  ? args.categories
  : ["bug", "feature", "question", "docs", "other"];
const goal = args?.goal || "入力群を分類し、種別ごとの対応方針を決める";

// item を文字列へ正規化
const items = rawItems
  .map(it => (typeof it === "string" ? it : (it?.text || it?.title || JSON.stringify(it))))
  .filter(s => s && s.trim());

log(`🗂️ Classify-and-act 開始: ${items.length} 件 / カテゴリ [${categories.join(", ")}]`);

if (items.length === 0) {
  log("⚠️ 処理対象がありません。args.items に配列を渡してください。");
  return { classified: {}, actions: [], note: "no items" };
}

// --- Classify: 全 item を許可カテゴリのいずれかへ分類 ---
phase("Classify");
const classifyResult = await agent(
  `全体目的: "${goal}"\n\n` +
  `次の ${items.length} 件を、必ず許可カテゴリ [${categories.join(", ")}] のいずれかに分類してください。\n\n` +
  `対象:\n${items.map((it, i) => `${i + 1}. ${it}`).join("\n")}\n\n` +
  `各 item に category（許可リスト内のみ）・confidence(0〜1)・reason を付けてください。` +
  `判断に迷うものは confidence を低くし、最も近いカテゴリを選んでください。`,
  { label: "classify:all", phase: "Classify", schema: buildClassifySchema(categories) }
);

const classifications = (classifyResult?.classifications || []).filter(c => c && c.category);

// カテゴリごとにグルーピング
const byCategory = {};
for (const c of classifications) {
  (byCategory[c.category] = byCategory[c.category] || []).push(c);
}
const usedCategories = Object.keys(byCategory);
log(`📊 分類完了: ${usedCategories.map(cat => `${cat}=${byCategory[cat].length}`).join(" / ")}`);

// --- Act: 種別ごとにハンドラ agent を並列起動 (各 agent に目的を再注入) ---
phase("Act");
const actions = await parallel(
  usedCategories.map(cat => () => agent(
    `全体目的: "${goal}"\n\n` +
    `あなたは「${cat}」カテゴリ専任のハンドラです。以下の ${byCategory[cat].length} 件について、\n` +
    `このカテゴリに適した対応方針を立ててください:\n\n` +
    byCategory[cat].map((c, i) => `${i + 1}. ${c.item}${c.reason ? `（分類理由: ${c.reason}）` : ""}`).join("\n") +
    `\n\n以下を日本語で出力してください:\n` +
    `1. このカテゴリ群への推奨アクション（具体的に）\n` +
    `2. 優先順位（高い順）\n` +
    `3. ClaudeOS 上での扱い（Issue 化 / ラベル / 担当ロール）`,
    { label: `act:${cat}`, phase: "Act" }
  ).then(plan => ({ category: cat, count: byCategory[cat].length, plan })))
);

// --- Summarize: 分布と対応方針を統合報告 ---
phase("Summarize");
const summary = await agent(
  `全体目的 "${goal}" の分類・対応を統合報告してください。\n\n` +
  `分類分布:\n${usedCategories.map(cat => `- ${cat}: ${byCategory[cat].length} 件`).join("\n")}\n\n` +
  `各カテゴリの対応方針:\n` +
  actions.filter(Boolean).map(a => `### ${a.category} (${a.count}件)\n${a.plan}`).join("\n\n") +
  `\n\n全体を俯瞰して、最優先で着手すべきカテゴリと次アクションを日本語でまとめてください。`,
  { label: "summarize:all", phase: "Summarize" }
);

return {
  goal,
  total: items.length,
  distribution: Object.fromEntries(usedCategories.map(cat => [cat, byCategory[cat].length])),
  classified: byCategory,
  actions: actions.filter(Boolean),
  summary,
};
