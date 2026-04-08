# ClaudeOS v7.1 セッション開始

## LOOP_COMMANDS

/loop 30m ClaudeOS Monitor
/loop 2h ClaudeOS Development
/loop 1h ClaudeOS Verify
/loop 1h ClaudeOS Improvement

## PROMPT_BODY

.claude/CLAUDE.md のセクション 0「セッション開始時の自動実行」に従い、以下を順番に実行してください。

1. 下記のループコマンド 4 本を /loop スキルで登録
2. /codex:setup を実行
3. /codex:status を確認
4. Memory MCP から前回セッションの残課題・再開ポイントを復元
5. GitHub Projects / Issues / CI の現在状態を確認
6. Monitor フェーズから自律開発を開始

Agent Teams を活用し、全プロセスを可視化してください。
README.md、ドキュメント、GitHub Projects は常に最新状態を維持してください。

登録するループコマンド:
