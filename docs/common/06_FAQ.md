# よくある質問

---

## Q1. Windows だけで使えますか？

はい。`-Local` を使えば Windows ローカルで起動できます。SSH は Linux 上で動かしたい場合だけ必要です。

---

## Q2. Copilot は何を前提にしていますか？

現行構成では `GitHub Copilot CLI` を `gh copilot` 前提で扱います。`gh auth login` と `gh extension install github/gh-copilot` が必要です。

---

## Q3. Claude Code と Codex CLI は API キー必須ですか？

必須ではありません。サブスクリプション認証でも使えます。

- Claude Code: `claude` 起動後に `/login`
- Codex CLI: `codex --login`

API 利用時のみ環境変数を設定します。

---

## Q4. プロジェクトはどこから選ばれますか？

- ローカル起動: `projectsDir`
- SSH 起動: `sshProjectsDir`

`-Project` を明示すれば選択をスキップできます。

---

## Q5. 共有ドライブが見えない場合は？

`projectsDirUnc` の設定と `test-drive-mapping.ps1` の結果を確認してください。

```powershell
.\scripts\test\test-drive-mapping.ps1
```

---

## Q6. どのツールから始めるべきですか？

- 実装とレビューをまとめて任せたい: Claude Code
- 軽快な CLI 支援がほしい: Codex CLI
- GitHub 操作支援がほしい: GitHub Copilot CLI

---

## Q7. tmux や DevTools は必須ですか？

いいえ。現行構成の標準フローでは必須ではありません。旧構成由来の説明は現在の標準運用ではありません。

---

## Q8. テストはありますか？

あります。現時点では Pester による共通モジュール中心のテストです。

```powershell
Invoke-Pester .\tests\
```
