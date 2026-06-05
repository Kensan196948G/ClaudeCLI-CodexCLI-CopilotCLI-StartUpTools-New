// gate-verification-sweep — 検証チェックリスト全項目を「1項目=1検証」で並列スイープ
// ---------------------------------------------------------------------------
// 出典: dynamic workflows "Memory & Rule Adherence / rule-verifier" パターン
//   (Thariq Shihipar & Sid Bidasaria, 2026-06-02
//    "A harness for every task: dynamic workflows in Claude Code")
//
// 対象: Claude/templates/claudeos/docs/webui-full-verification-checklist.md (250項目)
// 目的: webui-full-verification-checklist の Gate-1/2/3 を人手に頼らず並列検証し、
//       CLAUDE.md §11 の終了報告「必須3区分」(実行した検証/未実行/未実行理由) を自動生成する。
//
// 使い方:
//   /gate-verification-sweep                                   (gate-1 既定)
//   args 例: { "gate": "gate-3", "skipConditions": ["no_mobile_support","no_PWA"],
//              "batchSize": 8, "appUrl": "http://localhost:3737" }
//
//   gate     : "gate-1" | "gate-2" | "gate-3" | "all"  (既定 gate-1)
//   batchSize: 1検証エージェントが担当する項目数        (既定 10。1 で完全 1:1)
//   skipConditions: このプロジェクトで真の skip_if キーワード配列 (例 no_mobile_support)
//   changedFilesHint: gate-2 用。変更ファイルパス配列 (近傍項目の判定に使用)
//   appUrl   : E2E/Playwright 項目で叩く起動済み URL (無ければ E2E は not_run)
//   checklistPath: チェックリストのパス上書き (既定: 自動探索)
// ---------------------------------------------------------------------------

export const meta = {
  name: "gate-verification-sweep",
  description: "検証チェックリスト全項目を1項目=1検証エージェントで並列スイープし、終了報告3区分(実行/未実行/未実行理由)を自動生成",
  phases: [
    { title: "Preflight",  detail: "共有の自動チェック(lint/build/typecheck/test/security)を1回だけ実行" },
    { title: "Parse",      detail: "チェックリストを解析し Gate で対象項目を絞り込み" },
    { title: "Verify",     detail: "項目バッチごとに検証エージェントが並列で実検証" },
    { title: "Synthesize", detail: "終了報告3区分レポート + STABLE ゲート判定を生成" },
  ],
};

// --- スキーマ定義 ----------------------------------------------------------

const PREFLIGHT_SCHEMA = {
  type: "object",
  required: ["checks"],
  properties: {
    checks: {
      type: "array",
      items: {
        type: "object",
        required: ["name", "status", "summary"],
        properties: {
          name:    { type: "string" },                                   // lint/build/typecheck/unit/security/e2e
          command: { type: "string" },                                   // 実行コマンド (無ければ空)
          status:  { type: "string", enum: ["pass", "fail", "skip", "not_available"] },
          summary: { type: "string" },                                   // 結果要約 (失敗時は要点)
        },
      },
    },
  },
};

const PARSE_SCHEMA = {
  type: "object",
  required: ["gate", "total_in_file", "selected", "items"],
  properties: {
    gate:          { type: "string" },
    total_in_file: { type: "number" },
    selected:      { type: "number" },
    items: {
      type: "array",
      items: {
        type: "object",
        required: ["num", "name", "mandatory", "method", "timing", "skip_if", "skip_planned"],
        properties: {
          num:           { type: "number" },
          name:          { type: "string" },
          mandatory:     { type: "string", enum: ["必須", "条件", "任意"] },
          method:        { type: "string" },                             // 自動/半自動/目視
          timing:        { type: "string" },                             // PR/merge/nightly/release/incident
          evidence_type: { type: "string" },
          skip_if:       { type: "string" },
          skip_planned:  { type: "boolean" },                            // skipConditions により事前スキップ確定
        },
      },
    },
  },
};

const VERIFY_SCHEMA = {
  type: "object",
  required: ["results"],
  properties: {
    results: {
      type: "array",
      items: {
        type: "object",
        required: ["num", "name", "status", "evidence", "reason"],
        properties: {
          num:      { type: "number" },
          name:     { type: "string" },
          status:   { type: "string", enum: ["pass", "fail", "skip", "not_run", "blocked"] },
          evidence: { type: "string" },   // コマンド出力要約 / file:line / screenshot パス
          reason:   { type: "string" },   // skip/not_run/fail/blocked では必須。pass では空可
        },
      },
    },
  },
};

// --- 入力 ------------------------------------------------------------------

const gate          = (args?.gate || "gate-1").toLowerCase();
const batchSize     = Math.max(1, Number(args?.batchSize) || 10);
const skipConditions = Array.isArray(args?.skipConditions) ? args.skipConditions : [];
const changedFiles  = Array.isArray(args?.changedFilesHint) ? args.changedFilesHint : [];
const appUrl        = args?.appUrl || "";
const checklistPath = args?.checklistPath || "";

// gate ごとの選別ルール (Parse エージェントへ渡す自然言語仕様)
const GATE_RULES = {
  "gate-1": "必須度=「必須」かつ タイミング=「PR」 の項目のみ選別。",
  "gate-2": "(必須度=「必須」かつ タイミング∈{PR,merge}) に加え、主要回帰項目 #1・#22・#31・#51・#71・#111・#131・#141・#231〜#241 を必ず含める。" +
            (changedFiles.length ? ` さらに変更ファイル [${changedFiles.join(", ")}] に関連する項目も含める。` : ""),
  "gate-3": "必須度∈{「必須」,「条件」} の全項目を選別 (release スイープ)。「任意」は除外。",
  "all":    "全250項目を選別。",
};
const gateRule = GATE_RULES[gate] || GATE_RULES["gate-1"];

log(`🧪 Gate 検証スイープ開始 — gate=${gate} / batchSize=${batchSize}`);
if (skipConditions.length) log(`⏭ 事前スキップ条件: ${skipConditions.join(", ")}`);
if (budget?.total) log(`📊 token 予算: 残 ${Math.round(budget.remaining() / 1000)}k`);

// --- Phase 1: Preflight (共有自動チェックを1回だけ) ------------------------

phase("Preflight");
const preflight = await agent(
  `このプロジェクトの標準的な自動品質チェックを「1回だけ」実行し、結果を構造化して返してください。\n` +
  `package.json があれば scripts (lint/build/typecheck/test 等) を確認して実行。\n` +
  `PowerShell 主体なら PSScriptAnalyzer / Pester、Node なら npm audit、Python なら対応ツールを使用。\n` +
  `各チェックは name(lint/build/typecheck/unit/security/e2e 等)・command・status(pass/fail/skip/not_available)・summary を返す。\n` +
  `存在しないチェックは status=not_available とし、無理に実行しないこと。これは後続の各項目検証で共有する基準値です。`,
  { label: "preflight:auto-checks", phase: "Preflight", schema: PREFLIGHT_SCHEMA }
);
const preflightText = (preflight?.checks || [])
  .map(c => `- ${c.name} [${c.status}] ${c.command ? `(${c.command}) ` : ""}${c.summary}`)
  .join("\n") || "(自動チェック結果なし)";
log(`✅ Preflight 完了: ${(preflight?.checks || []).length} 種`);

// --- Phase 2: Parse (チェックリスト解析 + Gate 絞り込み) -------------------

phase("Parse");
const parsed = await agent(
  `検証チェックリストを読み、対象項目を構造化して返してください。\n\n` +
  `【手順】\n` +
  `1. チェックリストを探して読む: ${checklistPath ? `パス "${checklistPath}"` :
     `Glob "**/webui-full-verification-checklist.md" で探索し、.claude/claudeos/docs/ 配下を優先`}。\n` +
  `2. 各セクションの表 (列: # / 項目名 / 必須度 / 実行方法 / 担当Agent / タイミング / 証跡 / skip_if) を全行パースする。\n` +
  `3. 次の Gate ルールで選別する: ${gateRule}\n` +
  `4. 選別した各項目について、skip_if 値が次の事前スキップ条件配列 [${skipConditions.join(", ") || "なし"}] に含まれる場合は skip_planned=true とする (それ以外は false)。\n` +
  `5. total_in_file=ファイル内総項目数、selected=選別後件数、items=選別項目配列 を返す。\n` +
  `項目数が多い。要約せず、選別対象は1件も省略しないこと。`,
  { label: `parse:${gate}`, phase: "Parse", schema: PARSE_SCHEMA }
);

const items = (parsed?.items || []).filter(it => it && typeof it.num === "number");
log(`📋 解析完了: ファイル総数 ${parsed?.total_in_file ?? "?"} → ${gate} 選別 ${items.length} 件`);

if (items.length === 0) {
  log("⚠️ 対象項目が0件です。gate / checklistPath を確認してください。");
  return { gate, selected: 0, summary: "対象項目なし", report: "選別された検証項目がありませんでした。" };
}

// --- Phase 3: Verify (バッチごとに並列実検証) ------------------------------

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}
const batches = chunk(items, batchSize);
log(`🔁 検証バッチ ${batches.length} 個 (${batchSize}項目/バッチ) を並列スイープ`);

const verifyOut = await pipeline(
  batches,
  (batch, _orig, idx) => agent(
    `以下の検証項目バッチを「1項目ずつ実際に検証」してください。手抜き・一括 pass・捏造は厳禁です。\n\n` +
    `【共有 Preflight 結果 (自動チェックの基準値)】\n${preflightText}\n\n` +
    `${appUrl ? `【E2E/Playwright 用 URL】${appUrl} ← このアプリは起動済み・到達確認済み。\n` +
      `  画面操作が要る項目は Playwright MCP で「この URL に直接 navigate」して実検証すること。\n` +
      `  自前でサーバを起動し直さない (ポート不一致・二重起動の原因)。実際に使った URL を evidence に必ず残す。\n` +
      `  ${appUrl} が万一到達不能な場合のみ、起動コマンドとポートを evidence に明記した上で起動してよい。\n` +
      `  not_run にできるのは Playwright MCP 自体が使えない時、または E2E spec/ツールチェーンが repo に存在しない時に限る。\n\n`
      : `【E2E/Playwright】起動 URL 未指定。画面実操作が必要な項目はコードを確認のうえ not_run + 理由とすること。\n\n`}` +
    `【検証対象 (${batch.length}件)】\n${JSON.stringify(batch, null, 2)}\n\n` +
    `【各項目の status 判定基準】\n` +
    `- pass    : 実際に検証して問題なし。evidence にコマンド出力要約 / file:line / screenshot パス等の証跡を必ず記載。\n` +
    `- fail    : 検証して問題を確認。reason に何がどう失敗したかを記載。\n` +
    `- skip    : skip_planned=true、または skip_if 条件がこのプロジェクトで真。reason に該当条件を記載。\n` +
    `- not_run : この環境で検証不能 (人間の目視 / Staging / 実機 / 外部サービス依存等)。reason に不能理由を記載。\n` +
    `- blocked : 依存先の不具合で検証できない。reason に依存先を記載。\n\n` +
    `【厳守】証跡なく pass にしない。判断できなければ not_run + 正直な理由。自動項目は Preflight 結果を証跡に引用してよい。\n` +
    `Read/Grep/Bash 等で実際にコード・設定・コマンド結果を確認してから判定すること。`,
    { label: `verify:batch${idx + 1}/${batches.length}`, phase: "Verify", schema: VERIFY_SCHEMA }
  ).then(r => (r?.results || []))
);

const results = verifyOut.filter(Boolean).flat();

// --- 集計 (JS 側で確定。エージェントの自己申告に依存しない) ----------------

const byStatus = { pass: [], fail: [], skip: [], not_run: [], blocked: [] };
for (const r of results) (byStatus[r.status] || byStatus.not_run).push(r);

const itemByNum = new Map(items.map(it => [it.num, it]));
const mandatoryFail = byStatus.fail.filter(r => itemByNum.get(r.num)?.mandatory === "必須");
const mandatoryNotRun = byStatus.not_run.filter(r => itemByNum.get(r.num)?.mandatory === "必須");
const mandatoryBlocked = byStatus.blocked.filter(r => itemByNum.get(r.num)?.mandatory === "必須");

// STABLE ゲート: 必須項目に fail/blocked が無く、未検証(必須)が無いこと
const gatePassed = mandatoryFail.length === 0 && mandatoryBlocked.length === 0 && mandatoryNotRun.length === 0;

// 検証確定 (pass+fail) のうち pass の割合。not_run/skip は分母から除外し「実検証の質」を示す
const decided = byStatus.pass.length + byStatus.fail.length;
const verifiedPassRate = decided ? Math.round((byStatus.pass.length / decided) * 100) : 0;

const counts = {
  selected: items.length,
  verified: results.length,
  pass: byStatus.pass.length,
  fail: byStatus.fail.length,
  skip: byStatus.skip.length,
  not_run: byStatus.not_run.length,
  blocked: byStatus.blocked.length,
  verified_pass_rate: verifiedPassRate,
  mandatory_fail: mandatoryFail.length,
  mandatory_not_run: mandatoryNotRun.length,
  mandatory_blocked: mandatoryBlocked.length,
  gate_passed: gatePassed,
};

log(`📊 検証結果: ✅${counts.pass} ❌${counts.fail} ⏭${counts.skip} ⬜${counts.not_run} 🚧${counts.blocked} / 実検証合格率 ${verifiedPassRate}% / STABLE-Gate=${gatePassed ? "PASS" : "FAIL"}`);

// --- Phase 4: Synthesize (終了報告3区分レポート) --------------------------

phase("Synthesize");
const report = await agent(
  `以下の Gate 検証スイープ結果を、CLAUDE.md §11「終了報告の必須3区分」形式の日本語レポートにまとめてください。\n\n` +
  `gate=${gate} / 選別 ${counts.selected} 件 / 検証 ${counts.verified} 件\n` +
  `✅pass=${counts.pass} ❌fail=${counts.fail} ⏭skip=${counts.skip} ⬜not_run=${counts.not_run} 🚧blocked=${counts.blocked} / 実検証合格率=${verifiedPassRate}%\n` +
  `必須項目の未達: fail=${counts.mandatory_fail} not_run=${counts.mandatory_not_run} blocked=${counts.mandatory_blocked}\n` +
  `STABLE ゲート判定: ${gatePassed ? "PASS (必須項目すべて検証済み)" : "FAIL (必須項目に未達あり → merge/deploy 不可)"}\n\n` +
  `全結果:\n${JSON.stringify(results, null, 2)}\n\n` +
  `【出力フォーマット (この見出しを厳守)】\n` +
  `## 🧪 Gate 検証サマリー (${gate})\n` +
  `📊 ゲート判定: ${gatePassed ? "✅ PASS" : "❌ FAIL"}\n` +
  `### ✅ 実行した検証（件数・証跡）\n` +
  `  pass/fail 項目を番号・項目名・証跡付きで列挙。\n` +
  `### ⬜ 未実行の検証（件数・項目番号）\n` +
  `  not_run/blocked/skip 項目を番号で列挙。skip と not_run は区別する。\n` +
  `### 📝 未実行理由\n` +
  `  項目番号ごとに not_run/blocked/skip の理由を記載。\n` +
  `### ❌ 要対応 (fail / 必須未達)\n` +
  `  fail と 必須項目の not_run/blocked を最優先課題として列挙。無ければ「なし」。`,
  { label: "synthesize:report", phase: "Synthesize" }
);

log(gatePassed ? "🎉 STABLE-Gate PASS" : "⚠️ STABLE-Gate FAIL — 必須項目に未達あり");

return { gate, counts, summary: `gate=${gate} pass=${counts.pass}/${counts.verified} STABLE-Gate=${gatePassed ? "PASS" : "FAIL"}`, report, results };
