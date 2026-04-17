# reports/

ClaudeOS ループ実行中に生成される **揮発性レポート** を集約するディレクトリです。
ルート直下に散らばっていた `.loop-*.md` 等を 1 箇所にまとめ、生成物と手書き資産の
境界を明確化することが目的です（外部コードレビュー評価 #17 対応）。

## 置かれるもの

| ファイル | 生成元 | 追跡 | 現状 |
|---|---|---|---|
| `.loop-monitor-report.md` | `.claude/claudeos/loops/monitor-loop.md` Monitor ループ | ignored | ✅ 本 PR で移行済 |
| `.loop-build-report.md` | Build ループ（将来） | ignored | ⏳ 各 loop 定義 (`.claude/claudeos/loops/*.md`) の Output 更新待ち |
| `.loop-verify-report.md` | Verify ループ（将来） | ignored | ⏳ 同上 |
| `.loop-improve-report.md` | Improvement ループ（将来） | ignored | ⏳ 同上 |

> 現時点では Monitor のみが `reports/` 配下に出力します。Build / Verify / Improvement の各
> loop は出力先がプロジェクトルート（`.loop-*-report.md`）のままで、順次 `reports/` へ
> 統合していく方針です（別 Issue）。

## 置かれないもの

- `testResults.xml` は `.gitignore` 済。移動は Pester `-CI` スイッチと
  `.github/workflows/ci.yml` の整合調整を要するため、別 Issue で扱います。
- 手書きドキュメント類は `docs/` 配下、規範文書は `CLAUDE.md` / `AGENTS.md` に
  留めます（評価 #18 生成物と手書きの分離）。

## ルール

- このディレクトリ直下の **`.loop-*.md`** は全て `.gitignore` 対象です
- `README.md`（本ファイル）のみ追跡します
- 新しい生成物を追加するときは、命名規則を `[phase]-[purpose].[ext]` に揃えてください
