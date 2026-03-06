# ChromeDevTools事前到達性ゲート

- 種別: 機能アイデア（未実装）
- 前提: 固定PC運用（Windows 11 → Ubuntu SSH）、管理者権限でバッチ実行、ネットワーク常時接続、ChromeDevTools利用可能
- 目的: 起動前にChrome DevToolsのエンドポイント到達性を必須チェックし、未到達なら処理を止める。
- 期待効果: 前提崩れでの無駄な起動を防ぎ、原因切り分けが早くなる。
- アイデア詳細: http://localhost:PORT/json/version と Linux側到達チェックを二段で実施する。
- 実装段階: 企画/検討中（実装はまだ行わない）
