# reports/

ClaudeOS ループ実行中に生成される **揮発性レポート** を集約するディレクトリです。
ルート直下に散らばっていた `.loop-*.md` 等を 1 箇所にまとめ、生成物と手書き資産の
境界を明確化することが目的です（外部コードレビュー評価 #17 対応）。

## 置かれるもの

| ファイル | 生成元 | 追跡 | 現状 |
|---|---|---|---|
| `.loop-monitor-report.md` | `.claude/claudeos/loops/monitor-loop.md` Monitor ループ | ignored | ✅ 移行済 |
| `.loop-build-report.md` | Build ループ | ignored | ⏳ 各 loop 定義の Output 更新待ち |
| `.loop-verify-report.md` | Verify ループ | ignored | ⏳ 同上 |
| `.loop-improve-report.md` | Improvement ループ | ignored | ⏳ 同上 |
| `testResults.xml` | `Invoke-Pester` (CI) | ignored | ✅ v3.2.20 で CI 出力先を `reports/` へ移行 |
| `playwright-test*.png` | Playwright MCP スクリーンショット | ignored | ✅ `.gitignore` 対象 (ルート残存分も同パターンで無視) |

> Build / Verify / Improvement の各 loop は出力先がプロジェクトルート（`.loop-*-report.md`）の
> ままで、順次 `reports/` へ統合していく方針です（別 Issue）。

## 置かれないもの

- 手書きドキュメント類は `docs/` 配下、規範文書は `CLAUDE.md` / `AGENTS.md` に留めます。
- `state.json` はシステム中枢（CLAUDE.md §4）のためルートに残します。

## ルール

- このディレクトリ直下の **`.loop-*.md`** は全て `.gitignore` 対象です
- `README.md`（本ファイル）のみ追跡します
- 新しい生成物を追加するときは、命名規則を `[phase]-[purpose].[ext]` に揃えてください
