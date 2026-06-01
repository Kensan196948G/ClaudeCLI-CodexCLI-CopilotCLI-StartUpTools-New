export const meta = {
  name: "feature-development",
  description: "フィーチャーを Backend/Frontend/Test の3チームが並列実装し、統合・レビューまで完結",
  phases: [
    { title: "Design",      detail: "Architect がアーキテクチャ設計・タスク分解" },
    { title: "Implement",   detail: "Backend/Frontend/Test が並列実装" },
    { title: "Integrate",   detail: "統合確認・CI ステータス確認" },
  ],
};

const DESIGN_SCHEMA = {
  type: "object",
  required: ["architecture", "backend_tasks", "frontend_tasks", "test_tasks"],
  properties: {
    architecture:    { type: "string" },
    backend_tasks:   { type: "array", items: { type: "string" } },
    frontend_tasks:  { type: "array", items: { type: "string" } },
    test_tasks:      { type: "array", items: { type: "string" } },
    files_to_create: { type: "array", items: { type: "string" } },
    files_to_modify: { type: "array", items: { type: "string" } },
  },
};

const featureDescription = args?.feature || "実装する機能を args.feature に渡してください";
const issueNumber = args?.issue ? `Issue #${args.issue}` : "";

log(`🚀 機能実装開始: ${featureDescription} ${issueNumber}`);

phase("Design");
const design = await agent(
  `機能: "${featureDescription}" ${issueNumber ? `(${issueNumber})` : ""}\n\n` +
  `現在のコードベースを分析して、この機能の実装設計を行ってください:\n` +
  `1. アーキテクチャ概要（どのファイルをどう変更するか）\n` +
  `2. Backend タスクリスト（API/DB/ビジネスロジック）\n` +
  `3. Frontend タスクリスト（UI/UX/状態管理）\n` +
  `4. テストタスクリスト（Unit/Integration/E2E）\n` +
  `各タスクは独立して実装できる粒度に分解してください。`,
  { label: "design:architect", phase: "Design", schema: DESIGN_SCHEMA }
);

if (!design) {
  log("❌ 設計フェーズ失敗");
  return { error: "Design phase failed" };
}

log(`📐 設計完了 → Backend ${design.backend_tasks.length}タスク / Frontend ${design.frontend_tasks.length}タスク / Test ${design.test_tasks.length}タスク`);

phase("Implement");
const [backendResult, frontendResult, testResult] = await parallel([
  () => agent(
    `機能: "${featureDescription}"\n\n` +
    `担当: Backend 実装\n` +
    `アーキテクチャ: ${design.architecture}\n\n` +
    `実装タスク:\n${design.backend_tasks.map((t, i) => `${i+1}. ${t}`).join("\n")}\n\n` +
    `変更ファイル候補: ${design.files_to_modify?.join(", ")}\n` +
    `上記タスクを実装してください。テストは test チームが担当するので、ロジック実装に集中してください。`,
    { label: "impl:backend", phase: "Implement" }
  ),
  () => agent(
    `機能: "${featureDescription}"\n\n` +
    `担当: Frontend 実装\n` +
    `アーキテクチャ: ${design.architecture}\n\n` +
    `実装タスク:\n${design.frontend_tasks.map((t, i) => `${i+1}. ${t}`).join("\n")}\n\n` +
    `上記タスクを実装してください。Backend API は別チームが実装します。型定義・インターフェースを先に定義して進めてください。`,
    { label: "impl:frontend", phase: "Implement" }
  ),
  () => agent(
    `機能: "${featureDescription}"\n\n` +
    `担当: テスト実装\n` +
    `アーキテクチャ: ${design.architecture}\n\n` +
    `テストタスク:\n${design.test_tasks.map((t, i) => `${i+1}. ${t}`).join("\n")}\n\n` +
    `テストを先行実装（TDD）してください。実装コードが未完成でもテストは書けます。モックを活用し、インターフェースに対してテストを書いてください。`,
    { label: "impl:test", phase: "Implement" }
  ),
]);

phase("Integrate");
const integration = await agent(
  `機能 "${featureDescription}" の実装が完了しました。統合確認を行ってください:\n\n` +
  `1. git diff --stat で変更ファイルを確認\n` +
  `2. テストを実行して全件通過を確認\n` +
  `3. lint/typecheck を実行\n` +
  `4. CI 状態を確認（gh run list --limit 3）\n` +
  `5. PR 作成準備（変更内容・テスト結果・影響範囲をまとめる）\n\n` +
  `問題があれば修正してください。`,
  { label: "integrate:verify", phase: "Integrate" }
);

return {
  design,
  implementation: { backend: backendResult, frontend: frontendResult, tests: testResult },
  integration,
};
