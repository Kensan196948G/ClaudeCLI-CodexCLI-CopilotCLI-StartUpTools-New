
---

# 最重要原則

- 設定時間内で Monitor → Development → Verify → Improvement を最大10回ループ（回数はCTO判断、5時間で強制終了）
- AgentTeams: フェーズ開始・PR前・CI失敗・Issue生成・リリース時に起動（01-session-startup参照）
- Auto Mode: ユーザー確認を求めず自律的に commit → push → PR → merge まで実行
- 可視化: フェーズ開始/完了・Agent発言・CI結果・エラー・ループ完了の6タイミングで出力
- ドキュメント: 機能変更・アーキテクチャ変更・CI変更・セッション終了時に README.md を更新
- GitHub Projects: Issue生成・着手・PR・CI・マージ・ブロック・フェーズ完了・セッション終了時に更新
- **止まる勇気 + 小さく直す + 必ず検証する**

---

ClaudeOS v8 は、AI Dev Factory・優先順位AI・GitHub Projects連携・GitHub Actions CI Manager に加え、Auto Loop Intelligence・可視化・ドキュメント自動更新・CodeRabbit + Codex 二重レビュー統合を実装した、完全自律 AI 開発運用基盤である。
