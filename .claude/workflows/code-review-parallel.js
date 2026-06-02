export const meta = {
  name: "code-review-parallel",
  description: "PR を Security/Performance/TestCoverage の3視点で並列レビューし、統合レポートを生成",
  phases: [
    { title: "Review", detail: "3エージェントが独立したレビュー観点で同時レビュー" },
    { title: "Verify", detail: "各指摘を独立エージェントが adversarial 検証" },
    { title: "Synthesize", detail: "統合レポート生成" },
  ],
};

const REVIEW_SCHEMA = {
  type: "object",
  required: ["dimension", "findings"],
  properties: {
    dimension: { type: "string" },
    findings: {
      type: "array",
      items: {
        type: "object",
        required: ["title", "severity", "file", "description", "recommendation"],
        properties: {
          title:          { type: "string" },
          severity:       { type: "string", enum: ["critical", "high", "medium", "low"] },
          file:           { type: "string" },
          description:    { type: "string" },
          recommendation: { type: "string" },
        },
      },
    },
  },
};

const VERDICT_SCHEMA = {
  type: "object",
  required: ["isReal", "reasoning"],
  properties: {
    isReal:    { type: "boolean" },
    reasoning: { type: "string" },
  },
};

// Diff to review (defaults to main branch)
const baseBranch = args?.baseBranch || "main";

const DIMENSIONS = [
  {
    key: "security",
    prompt: `git diff ${baseBranch}...HEAD を取得し、セキュリティ観点でレビューしてください。
特に確認: XSS/CSRF/SQL Injection/IDOR/Path Traversal/SSRF/認証バイパス/シークレット漏洩/依存関係の脆弱性。
各指摘は severity(critical/high/medium/low)・file・description・recommendation を含めてください。`,
  },
  {
    key: "performance",
    prompt: `git diff ${baseBranch}...HEAD を取得し、パフォーマンス観点でレビューしてください。
特に確認: N+1 クエリ/不要なループ/メモリリーク/blocking I/O/大きなバンドルサイズ/キャッシュ未活用。
各指摘は severity(critical/high/medium/low)・file・description・recommendation を含めてください。`,
  },
  {
    key: "test-coverage",
    prompt: `git diff ${baseBranch}...HEAD を取得し、テストカバレッジ観点でレビューしてください。
特に確認: 変更ファイルに対応するテストの有無・エッジケースの未テスト・モックの過剰使用・E2E 不足。
各指摘は severity(critical/high/medium/low)・file・description・recommendation を含めてください。`,
  },
];

phase("Review");
const reviews = await pipeline(
  DIMENSIONS,
  d => agent(d.prompt, { label: `review:${d.key}`, phase: "Review", schema: REVIEW_SCHEMA })
);

const allFindings = reviews
  .filter(Boolean)
  .flatMap(r => (r.findings || []).map(f => ({ ...f, dimension: r.dimension })));

if (allFindings.length === 0) {
  log("✅ 指摘なし — レビュー完了");
  return { summary: "No issues found", findings: [] };
}

log(`🔍 指摘 ${allFindings.length} 件 → adversarial 検証へ`);

phase("Verify");
const verified = await pipeline(
  allFindings,
  f => agent(
    `以下の指摘を adversarial に検証してください。本当に問題があるか、誤検知でないかを評価してください。\n\n` +
    `指摘: ${f.title}\n` +
    `観点: ${f.dimension}\n` +
    `ファイル: ${f.file}\n` +
    `説明: ${f.description}\n\n` +
    `デフォルトは isReal=false (疑わしければ誤検知扱い)。明確な問題がある場合のみ isReal=true。`,
    { label: `verify:${f.file}:${f.severity}`, phase: "Verify", schema: VERDICT_SCHEMA }
  ).then(v => v ? { ...f, verdict: v } : null)
);

const confirmed = verified.filter(Boolean).filter(f => f.verdict?.isReal);
const bySeverity = { critical: [], high: [], medium: [], low: [] };
for (const f of confirmed) {
  (bySeverity[f.severity] || bySeverity.low).push(f);
}

phase("Synthesize");
const report = await agent(
  `以下のコードレビュー結果を日本語で統合レポートにまとめてください。\n\n` +
  `Critical: ${bySeverity.critical.length}件\n` +
  `High: ${bySeverity.high.length}件\n` +
  `Medium: ${bySeverity.medium.length}件\n` +
  `Low: ${bySeverity.low.length}件\n\n` +
  `各指摘の詳細:\n${JSON.stringify(confirmed, null, 2)}\n\n` +
  `レポートには: エグゼクティブサマリー / Critical・High の必須修正リスト / Medium 推奨修正 / Low 任意対応 を含めてください。`,
  { label: "synthesize:report", phase: "Synthesize" }
);

return {
  summary: `Critical=${bySeverity.critical.length} High=${bySeverity.high.length} Medium=${bySeverity.medium.length} Low=${bySeverity.low.length}`,
  confirmed,
  report,
};
