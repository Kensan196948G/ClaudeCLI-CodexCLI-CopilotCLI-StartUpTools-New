## LOOP_COMMANDS
Claude 起動後、最初に以下の 4 コマンドをこの順番で登録してください。

1. /loop 1h ClaudeOS Monitor
2. /loop 2h ClaudeOS Development
3. /loop 2h ClaudeOS Verify
4. /loop 3h ClaudeOS Improvement

各コマンドの登録完了を確認してから次へ進んでください。
4 本すべての登録が完了するまで、通常の開発作業は開始しないでください。

## PROMPT_BODY
以降、日本語で対応・解説してください。

このリポジトリでは `.claude/CLAUDE.md` と `.claude/claudeos` を正規構成として参照し、
ClaudeOS v5 ベストプラクティスに従って自律開発を進めてください。

今回の前提:
- プロジェクト名: {記入}
- 目的: {記入}
- 技術スタック: {記入}
- 準拠規格: {記入}

作業ルール:
- 最大 8 時間、Loop Guard 最優先
- ループは Monitor → Build → Verify → Improve
- ループ判定は時間ではなく主作業内容ベース
- 小変更では Agent Teams を濫用しない
- main 直接 push 禁止
- branch または WorkTree 必須
- PR 必須
- CI 成功のみ merge
- STABLE 未達では merge / deploy 禁止
- 参照できない GitHub / CI / MCP 状態は推測しない

セッション開始時に実施:
1. 現状把握
2. 今回の成功条件整理
3. 触るファイルと影響範囲の明確化
4. 必要なら Agent Teams / WorkTree の要否判断

セッション終了時に必ず実施:
1. 現在の作業内容整理
2. test / lint / build / CI 結果整理
3. 残課題と再開ポイント整理
4. README 更新要否の確認
5. 最終報告出力
