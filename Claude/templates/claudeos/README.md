# ClaudeOS Template Source — 編集元（正本）

> **このディレクトリは ClaudeOS カーネルの正本（編集元）です。**
> 変更はここに加え、`.claude/claudeos/` へ同期してください。

## 役割

| ディレクトリ | 役割 | 編集可否 |
|---|---|---|
| `Claude/templates/claudeos/` (本ディレクトリ) | **正本・編集元** | ✅ ここを編集する |
| `.claude/claudeos/` | 配備先（runtime copy） | ❌ 直接編集禁止 |
| `scripts/templates/claudeos/` | Legacy（旧版） | ⚠️ 統合待ち、編集不要 |

## 同期方法

```powershell
# 編集後に .claude/claudeos/ へ同期
# （差分確認してから実行すること）
xcopy /E /I /Y "Claude\templates\claudeos" ".claude\claudeos"
```

詳細は `docs/SOURCE_OF_TRUTH.md` を参照。
