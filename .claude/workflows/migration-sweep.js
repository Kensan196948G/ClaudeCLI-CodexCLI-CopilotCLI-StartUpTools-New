// migration-sweep — コードベース横断の移行/リファクタを discover → transform → verify
// ---------------------------------------------------------------------------
// 出典: dynamic workflows "Migrations & Refactors" パターン
//   (Thariq Shihipar & Sid Bidasaria, 2026-06-02)
//
// 用途: SSH 名残削除・API 名称変更・依存差し替え等、多数のサイトに散らばる
//       機械的だが文脈依存の移行を、ファイル単位エージェントで並列適用する。
//
// 安全既定: apply=false (discover + 変更案レポートのみ。実ファイルは触らない)。
//           apply=true で実編集。プロジェクト全体の --dry-run/--apply 規約に準拠。
//
// 使い方:
//   /migration-sweep            (args 必須。下記)
//   args 例: {
//     "description": "SSH 経由実行を Windows ローカル実行へ置換",
//     "find": "ssh |Invoke-SSH|linuxHost",     // 対象サイトの検索語/正規表現
//     "globs": ["scripts/**/*.ps1","scripts/**/*.js"],  // 走査スコープ
//     "verifyCmd": "node --check",              // 変換後の検証 (任意)
//     "apply": false                            // true で実編集
//   }
// ---------------------------------------------------------------------------

export const meta = {
  name: "migration-sweep",
  description: "コードベース横断の移行/リファクタを discover→transform→verify で並列実行 (既定 dry-run・apply で実適用)",
  phases: [
    { title: "Discover",  detail: "移行対象サイトを横断検索しファイル単位に集約" },
    { title: "Transform", detail: "ファイル単位エージェントが変換 (apply 時のみ実編集)" },
    { title: "Verify",    detail: "検証コマンド実行 + 変更レビュー + レポート生成" },
  ],
};

const DISCOVER_SCHEMA = {
  type: "object",
  required: ["files", "total_files", "total_sites"],
  properties: {
    total_files: { type: "number" },
    total_sites: { type: "number" },
    files: {
      type: "array",
      items: {
        type: "object",
        required: ["path", "occurrences", "sites"],
        properties: {
          path:        { type: "string" },
          occurrences: { type: "number" },
          sites: {
            type: "array",
            items: {
              type: "object",
              required: ["line", "snippet", "reason"],
              properties: {
                line:    { type: "number" },
                snippet: { type: "string" },
                reason:  { type: "string" },
              },
            },
          },
        },
      },
    },
  },
};

const TRANSFORM_SCHEMA = {
  type: "object",
  required: ["path", "status", "changes", "note"],
  properties: {
    path:   { type: "string" },
    status: { type: "string", enum: ["transformed", "planned", "skipped", "failed"] },
    changes: {
      type: "array",
      items: {
        type: "object",
        required: ["line", "before", "after"],
        properties: {
          line:   { type: "number" },
          before: { type: "string" },
          after:  { type: "string" },
        },
      },
    },
    note: { type: "string" },
  },
};

const VERIFY_SCHEMA = {
  type: "object",
  required: ["status", "summary"],
  properties: {
    status:  { type: "string", enum: ["pass", "fail", "skip"] },
    summary: { type: "string" },
  },
};

// --- 入力 ------------------------------------------------------------------

const description = args?.description || "";
const find        = args?.find || "";
const globs       = Array.isArray(args?.globs) ? args.globs : [];
const verifyCmd   = args?.verifyCmd || "";
const apply       = args?.apply === true;

if (!description || !find) {
  log("⚠️ args.description と args.find は必須です。中止します。");
  return { error: "args.description と args.find が必要", description, find };
}

log(`🔧 migration-sweep — ${apply ? "⚡ APPLY (実編集)" : "🔍 DRY-RUN (変更案のみ)"}`);
log(`🎯 目標: ${description}`);
log(`🔎 検索: ${find}${globs.length ? ` / scope: ${globs.join(", ")}` : ""}`);
if (budget?.total) log(`📊 token 予算: 残 ${Math.round(budget.remaining() / 1000)}k`);

// --- Phase 1: Discover -----------------------------------------------------

phase("Discover");
const discovered = await agent(
  `移行対象サイトを横断検索してファイル単位に集約してください。\n\n` +
  `【移行目標】${description}\n` +
  `【検索語/正規表現】${find}\n` +
  `【走査スコープ】${globs.length ? globs.join(", ") : "リポジトリ全体 (node_modules/.git/dist は除外)"}\n\n` +
  `Grep/Glob で全該当箇所を洗い出し、ファイルごとに occurrences と sites(line/snippet/該当理由) を集約。\n` +
  `移行目標に照らして「変更すべき箇所」のみ含める (誤検知・コメント内の無関係一致は除外)。\n` +
  `1件も省略せず、total_files / total_sites も返すこと。`,
  { label: "discover", phase: "Discover", schema: DISCOVER_SCHEMA }
);

const files = (discovered?.files || []).filter(f => f && f.path);
log(`📋 発見: ${discovered?.total_files ?? files.length} ファイル / ${discovered?.total_sites ?? "?"} サイト`);

if (files.length === 0) {
  log("✅ 対象サイトなし — 移行不要、または検索語の見直しが必要");
  return { apply, discovered: { total_files: 0, total_sites: 0 }, transformed: [], summary: "対象サイトなし" };
}

// --- Phase 2: Transform (ファイル単位・並列) -------------------------------
// ファイル単位に分離しているため同一ファイルの並列編集衝突は起きない。
// worktree 隔離は使わない (変更を本ブランチへ着地させるため)。

phase("Transform");
log(`🔁 ${files.length} ファイルを${apply ? "変換" : "変換案作成"} (並列)`);

const transformed = await pipeline(
  files,
  (f) => agent(
    `次の1ファイルだけを移行対象として扱ってください (他ファイルには触れない)。\n\n` +
    `【移行目標】${description}\n` +
    `【対象ファイル】${f.path}\n` +
    `【該当サイト】\n${JSON.stringify(f.sites, null, 2)}\n\n` +
    (apply
      ? `【APPLY モード】実際に Edit/Write でこのファイルを編集してください。\n` +
        `- 周辺コードのスタイル・命名・コメント密度に合わせる\n` +
        `- 挙動を変えない (純粋な移行)。判断に迷う箇所は編集せず note に残す\n` +
        `- 編集後に node --check 等で壊れていないか確認\n` +
        `- 実施した変更を changes(line/before/after) に列挙し status=transformed\n` +
        `- 変更不要だった場合 status=skipped`
      : `【DRY-RUN モード】ファイルは編集しないでください。\n` +
        `- 各サイトの変更案を changes(line/before/after) として提示\n` +
        `- status=planned (変更案あり) / skipped (変更不要)\n` +
        `- リスク・要確認点は note に記載`) +
    `\nファイルを Read で実際に確認してから判断すること。`,
    { label: `${apply ? "apply" : "plan"}:${f.path.split(/[\\/]/).pop()}`, phase: "Transform", schema: TRANSFORM_SCHEMA }
  )
);

const results = transformed.filter(Boolean);
const tStatus = { transformed: [], planned: [], skipped: [], failed: [] };
for (const r of results) (tStatus[r.status] || tStatus.failed).push(r);
const changedCount = (apply ? tStatus.transformed : tStatus.planned).length;
const totalChanges = results.reduce((n, r) => n + (r.changes?.length || 0), 0);
log(`📊 ${apply ? "変換" : "変換案"}: ${changedCount} ファイル / 変更 ${totalChanges} 箇所 / skip ${tStatus.skipped.length} / failed ${tStatus.failed.length}`);

// --- Phase 3: Verify -------------------------------------------------------

phase("Verify");
let verify = { status: "skip", summary: "apply=false のため検証スキップ" };

if (apply && (tStatus.transformed.length > 0)) {
  verify = await agent(
    `移行適用後の検証をしてください。\n\n` +
    `【移行目標】${description}\n` +
    `【変更ファイル】${tStatus.transformed.map(r => r.path).join(", ")}\n` +
    (verifyCmd ? `【検証コマンド】${verifyCmd} を変更ファイルに対して実行し結果を確認。\n` : `【検証】変更ファイルを node --check / 対応 linter 等で確認。\n`) +
    `さらに git diff を確認し、移行目標から外れた変更・残し漏れ・壊れた構文が無いか adversarial に点検。\n` +
    `status(pass/fail/skip) と summary を返す。`,
    { label: "verify", phase: "Verify", schema: VERIFY_SCHEMA }
  ) || verify;
  log(`🧪 検証: ${verify.status} — ${verify.summary}`);
}

// --- レポート --------------------------------------------------------------

const report = await agent(
  `移行スイープ結果を日本語レポートにまとめてください。\n\n` +
  `モード: ${apply ? "APPLY (実編集済)" : "DRY-RUN (変更案のみ)"}\n` +
  `目標: ${description}\n` +
  `発見: ${files.length} ファイル / ${discovered?.total_sites ?? "?"} サイト\n` +
  `${apply ? "変換" : "変換案"}: ${changedCount} ファイル / 変更 ${totalChanges} 箇所 / skip ${tStatus.skipped.length} / failed ${tStatus.failed.length}\n` +
  `検証: ${verify.status} — ${verify.summary}\n\n` +
  `詳細:\n${JSON.stringify(results, null, 2)}\n\n` +
  `レポート構成: ## 移行サマリー / ### 変更ファイル一覧 / ### 要確認・スキップ / ### 次アクション` +
  `${apply ? "" : " (apply=true で実適用する手順を含める)"}。`,
  { label: "report", phase: "Verify" }
);

return {
  apply,
  discovered: { total_files: files.length, total_sites: discovered?.total_sites },
  counts: { changed: changedCount, total_changes: totalChanges, skipped: tStatus.skipped.length, failed: tStatus.failed.length },
  verify,
  transformed: results,
  report,
};
