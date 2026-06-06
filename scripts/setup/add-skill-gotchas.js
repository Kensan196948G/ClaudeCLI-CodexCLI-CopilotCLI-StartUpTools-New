#!/usr/bin/env node
/**
 * add-skill-gotchas.js
 *
 * 主要 skill にドメイン固有の `## Gotchas（陥りやすい失敗）` セクションを挿入する
 * 保守スクリプト (Tier2)。
 *
 * 背景:
 *   全 SKILL.md は scaffold 生成で 概要〜注意点 まで汎用ボイラープレートのみ。
 *   Anthropic blog "Lessons from building Claude Code: How we use Skills" は
 *   最も信号価値が高いのは「Gotchas (よくある失敗点)」だと述べる。
 *   ここに各ドメインで実際に人を刺す失敗モードを集約し、skill の実効性を上げる。
 *
 * 設計:
 *   - GOTCHAS: フォルダ名 -> 箇条書き配列 (単一の真実)。
 *   - 挿入位置: `## 相性のよい command` の直前。無ければ `## 注意点` の直前。
 *   - 配布元テンプレと local copy の両方を処理する。
 *
 * 冪等性:
 *   既に `## Gotchas` を含む SKILL.md はスキップする。
 *
 * 使い方:
 *   node scripts/setup/add-skill-gotchas.js --dry-run
 *   node scripts/setup/add-skill-gotchas.js
 */

"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

const SKILL_DIRS = [
  path.join(REPO_ROOT, "Claude", "templates", "claudeos", "skills"),
  path.join(REPO_ROOT, ".claude", "claudeos", "skills"),
];

const DRY_RUN = process.argv.includes("--dry-run");

const SECTION_HEADING = "## Gotchas（陥りやすい失敗）";

// フォルダ名 -> ドメイン固有の失敗モード (実際に人を刺すものだけ)。
const GOTCHAS = {
  "docker-patterns": [
    "`latest` タグ依存で再現性が壊れる。digest 固定か明示バージョンタグを使う",
    "`.dockerignore` 未整備で `COPY . .` が `.git`/`node_modules`/secret を image へ焼き込む",
    "root 実行のまま放置。`USER` 指定と read-only rootfs を検討する",
    "`depends_on` は起動順を保証するが起動完了は保証しない。healthcheck + `condition: service_healthy` が要る",
    "マルチステージビルド未使用で build ツールチェーンを本番 image に残し肥大化させる",
    "secret を `build-arg` や ENV に渡すと image layer / `docker inspect` から漏れる",
    "Linux の bind mount は host uid/gid 差異でコンテナ内書込みが失敗する",
  ],
  "django-security": [
    "本番 `DEBUG=True` 残置で例外画面に settings と secret が露出する",
    "`ALLOWED_HOSTS` 未設定 / `[\"*\"]` で Host ヘッダ injection を許す",
    "`SECRET_KEY` をコード/リポジトリにハードコードする",
    "`.raw()` / `.extra()` / 文字列連結 SQL で ORM の injection 防御を迂回する",
    "`mark_safe` / `|safe` / `format_html` 誤用で XSS を作る",
    "`@csrf_exempt` の無自覚付与、SessionAuth の API で CSRF が抜ける",
    "`get_object_or_404` だけで所有者チェックを省き IDOR を作る",
    "session/CSRF cookie の `SECURE` / `HttpOnly` / `SameSite` 未設定",
  ],
  "django-patterns": [
    "`select_related` / `prefetch_related` 不足で N+1 クエリ",
    "QuerySet の遅延評価を理解せずループ内でクエリを発行する",
    "fat views / fat models で service 層の責務分離が崩れる",
    "model 変更後の `makemigrations` 忘れで schema と乖離する",
    "signals 多用で副作用の追跡が不能になる",
    "settings を環境分離せず単一 `settings.py` に `if` 分岐を詰め込む",
  ],
  "django-tdd": [
    "`TestCase`(トランザクション) と `TransactionTestCase` の差異を無視し flaky 化",
    "実 DB/外部 API に依存したテストで遅く不安定になる",
    "fixtures 肥大で意図が読めない。factory(`factory_boy`) で必要分だけ作る",
    "`setUp` の重い処理を毎テスト実行して遅くする (`setUpTestData` を使う)",
    "freeze せず `timezone.now()` 依存テストを書き時間で壊れる",
  ],
  "django-verification": [
    "migration の前進だけ確認し rollback(逆 migration) を検証しない",
    "permission/所有者チェックの検証を正常系だけで済ませる",
    "`makemigrations --check --dry-run` を CI に入れず未生成 migration を見逃す",
    "本番相当データ量での性能/タイムアウトを確認しない",
  ],
  "laravel-security": [
    "`$fillable` 未定義 + `$guarded=[]` で mass assignment (is_admin 等を更新される)",
    "`{!! !!}` の raw 出力で XSS。既定は `{{ }}` を使う",
    "`DB::raw()` / `whereRaw()` に未バインドのユーザー入力を渡す",
    "本番 `APP_DEBUG=true` 残置で Ignition がスタック/設定を露出する",
    "route に policy/`authorize` を付け忘れて IDOR を作る",
    "public disk 誤設定で非公開ファイルを `Storage::url` 経由で露出する",
    "`VerifyCsrfToken::$except` へ安易に追加して CSRF を抜く",
  ],
  "laravel-patterns": [
    "Eloquent の N+1。`with()` eager loading 不足 (Telescope/Debugbar で検出)",
    "controller に業務ロジック集中。service/action クラスへ分離する",
    "`Model::all()` を大量データに使いメモリ枯渇 (`chunk`/`cursor` を使う)",
    "queue job の冪等性欠如で再試行が二重実行になる",
    "実行時に `env()` を直接呼ぶと config cache で null になる。`config()` 経由にする",
  ],
  "laravel-tdd": [
    "Feature test で `RefreshDatabase` を付け忘れテスト間が汚染される",
    "実メール/実決済を mock せず外部に到達させる (`Mail::fake()` 等)",
    "factory の states を使わず重複したセットアップを量産する",
    "`assertDatabaseHas` だけで副作用(event/job)の検証を怠る",
  ],
  "laravel-verification": [
    "route/policy/queue/DB 更新のうち queue の非同期挙動を検証しない",
    "`php artisan route:list` で認可ミドルウェアの付与漏れを確認しない",
    "migration の rollback を本番相当データで検証しない",
    "config cache(`config:cache`) 後に挙動が変わる箇所を確認しない",
  ],
  "springboot-security": [
    "`.anyRequest().permitAll()` の取り残しで全公開になる",
    "REST 化で CSRF を全 disable するが cookie ベース認証が残り脆弱になる",
    "`@PreAuthorize` が self-invocation(同クラス内呼び出し)で効かない",
    "actuator(`/env`,`/heapdump`)を無認証で露出する",
    "`NoOpPasswordEncoder` / 平文でパスワードを保存する",
    "JWT で `alg=none` を受理 / secret が短小で総当たり可能",
    "CORS `allowedOrigins(\"*\")` と credentials を併用する",
  ],
  "springboot-patterns": [
    "`@Transactional` が self-invocation / private メソッドで無効になる",
    "field injection でテスト困難化。constructor injection にする",
    "`application.properties` に secret 直書き (profile/vault 分離する)",
    "JPA entity を controller から直接返し lazy 例外・過剰公開を招く (DTO 化)",
    "読取専用処理に `@Transactional(readOnly=true)` を付けず不要 dirty checking が走る",
  ],
  "springboot-tdd": [
    "`@SpringBootContext` 全起動を多用しテストが遅くなる (slice test を使う)",
    "`@MockBean` 乱用で実結線の不具合を検出できなくなる",
    "`@DataJpaTest` の組込 DB と本番 DB の方言差で漏れる",
    "test 用 `application.properties` の profile 分離漏れで本番設定を読む",
  ],
  "springboot-verification": [
    "起動・統合・DB 接続のうち lazy 関連の境界外アクセスを検証しない",
    "actuator/health endpoint の応答だけで実依存(DB/MQ)の死活を判断する",
    "flyway/liquibase の migration 適用順を本番相当で確認しない",
    "主要 API の異常系(401/403/409)の検証を省く",
  ],
  "golang-patterns": [
    "`err` を `_` で握りつぶす / wrap せず原因を失う (`fmt.Errorf(\"...: %w\", err)`)",
    "goroutine leak。context cancel / channel close 漏れを残す",
    "Go 1.22 未満の loop 変数キャプチャを goroutine/closure が共有する",
    "共有 map への並行書込みで data race (`-race` で検出する)",
    "nil map への書込み panic / nil interface 比較の落とし穴",
    "ループ内 `defer` の多用でリソース解放が関数末尾まで遅延する",
  ],
  "python-patterns": [
    "mutable default 引数 (`def f(x=[])`) で状態が共有される",
    "bare `except:` で例外を握りつぶす / 原因を失う",
    "`None` 比較に `==` を使う (`is None` が正)",
    "モジュールレベル副作用 / 循環 import で読込順に依存する",
    "CPU bound を thread で並列化して GIL に阻まれる (process/別実装へ)",
    "ログを f-string で先評価し遅延評価の利点を失う",
  ],
  "clickhouse-io": [
    "列指向なのに `SELECT *` で全列読込し I/O を浪費する",
    "行単位 INSERT を多発させ part 爆発 → merge 過負荷 (バッチ INSERT 必須)",
    "`FINAL` 常用で性能劣化 / ReplacingMergeTree の重複解消を即時と誤解する",
    "sorting key(`ORDER BY`)設計ミスで primary index が効かず full scan",
    "高カーディナリティの partition key で part 数が爆発する",
    "`ALTER UPDATE/DELETE`(mutation) を OLTP 的に使う (非同期・高コスト)",
    "`Nullable` 乱用でストレージと性能を劣化させる",
  ],
  "postgres-patterns": [
    "`WHERE lower(col)=...` 等の関数適用で index が無効化する (式 index が要る)",
    "長時間トランザクションで VACUUM を阻害し bloat を招く",
    "`CREATE INDEX` を `CONCURRENTLY` 無しで実行し write lock を取る",
    "旧版で `ADD COLUMN ... DEFAULT` が full table rewrite + lock を引き起こす",
    "接続プール(pgbouncer 等)無しで接続枯渇する",
    "`SELECT *` + N+1 で過剰取得する",
    "`SERIALIZABLE` の競合 retry を実装しない",
  ],
  "database-migrations": [
    "rename/drop を deploy と同時実行し旧コードが落ちる (expand→contract の2段階に)",
    "後方互換を壊す変更を 1 migration に詰め込む",
    "大テーブルの DDL で長時間 lock (オンライン DDL / batched backfill)",
    "down migration(rollback)を未検証のまま出す",
    "data migration を schema migration に混在させる",
    "本番でしか出ない順序依存・seed 依存を見逃す",
  ],
  "deployment-patterns": [
    "readiness と liveness を混同し、起動中に traffic を流す",
    "rollback 手順未整備 / DB migration が rollback 不能",
    "ビルド時 env と実行時 env を混同する (12-factor 違反)",
    "secret を image / CI ログに露出する",
    "zero-downtime 前提なのに in-place restart で瞬断する",
    "canary/blue-green で新旧スキーマ非互換 (expand/contract で吸収する)",
  ],
  "e2e-testing": [
    "固定 `sleep`/`waitForTimeout` で flaky 化 (web-first assertion / auto-wait を使う)",
    "脆い CSS セレクタ依存。role/label/test-id ベースにする",
    "テスト間で DB/seed のリセットを怠り状態が漏れる",
    "認証を毎テスト UI 経由にする (storageState を使い回す)",
    "並列実行時のデータ競合を考慮しない",
    "`networkidle` 待ちを過信して不安定化させる",
  ],
  "jpa-patterns": [
    "N+1。`FetchType.EAGER` 乱用 or lazy + ループ (fetch join / `@EntityGraph`)",
    "session 外アクセスで `LazyInitializationException`",
    "`equals`/`hashCode` を生成 ID で実装する (永続化前は null)",
    "更新で `save()` を多用する (dirty checking で不要)",
    "cascade の過剰設定で意図しない delete が伝播する",
    "`@Transactional` 境界外での lazy load を前提にする",
  ],
};

/** Gotchas markdown ブロックを組み立てる。 */
function buildSection(bullets) {
  return (
    SECTION_HEADING +
    "\n\n" +
    bullets.map((b) => `- ${b}`).join("\n") +
    "\n\n"
  );
}

function processSkillFile(skillMdPath, bullets) {
  const original = fs.readFileSync(skillMdPath, "utf8");

  if (original.includes(SECTION_HEADING)) {
    return { status: "skip", reason: "Gotchas 既存" };
  }

  const section = buildSection(bullets);

  // 挿入アンカー: `## 相性のよい command` 優先、無ければ `## 注意点`。
  let anchor = "## 相性のよい command";
  if (!original.includes(anchor)) anchor = "## 注意点";
  if (!original.includes(anchor)) {
    return { status: "error", reason: "挿入アンカーが見つからない" };
  }

  const updated = original.replace(anchor, section + anchor);

  if (DRY_RUN) {
    return { status: "would-write" };
  }

  fs.writeFileSync(skillMdPath, updated, "utf8");
  return { status: "written" };
}

function main() {
  const totals = { written: 0, skip: 0, error: 0, wouldWrite: 0, missing: 0 };
  const errors = [];

  for (const dir of SKILL_DIRS) {
    if (!fs.existsSync(dir)) {
      console.log(`⚠️  ディレクトリ無し: ${path.relative(REPO_ROOT, dir)}`);
      continue;
    }
    console.log(`\n📁 ${path.relative(REPO_ROOT, dir)}`);

    for (const folderName of Object.keys(GOTCHAS).sort()) {
      const skillMdPath = path.join(dir, folderName, "SKILL.md");
      if (!fs.existsSync(skillMdPath)) {
        totals.missing++;
        console.log(`   ❓ ${folderName}: SKILL.md 無し`);
        continue;
      }
      const result = processSkillFile(skillMdPath, GOTCHAS[folderName]);
      switch (result.status) {
        case "written":
          totals.written++;
          console.log(`   ✅ ${folderName}`);
          break;
        case "would-write":
          totals.wouldWrite++;
          console.log(`   📝 ${folderName}`);
          break;
        case "skip":
          totals.skip++;
          console.log(`   ⏭️  ${folderName} (${result.reason})`);
          break;
        case "error":
          totals.error++;
          errors.push(`${folderName}: ${result.reason}`);
          console.log(`   ❌ ${folderName} (${result.reason})`);
          break;
      }
    }
  }

  console.log("\n📊 サマリ");
  console.log(`   ${DRY_RUN ? "付与予定" : "付与"}: ${DRY_RUN ? totals.wouldWrite : totals.written}`);
  console.log(`   スキップ(既存): ${totals.skip}`);
  console.log(`   SKILL.md 欠落: ${totals.missing}`);
  console.log(`   エラー: ${totals.error}`);

  if (errors.length > 0) {
    console.log("\n❌ エラー詳細:");
    errors.forEach((e) => console.log(`   - ${e}`));
    process.exit(1);
  }
}

main();
