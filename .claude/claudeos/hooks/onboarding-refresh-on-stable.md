# onboarding-refresh-on-stable

PostToolUse の通常フックとして起動する ONBOARDING.md 自動再生成器。
test / build / lint / typecheck 系ツールの完了後に、STABLE 判定が連続成功
閾値へ到達したタイミングを検出し、`/team-onboarding` を再実行して
`ONBOARDING.md` を最新化する。

本ファイルは静的なドキュメントではなく、**呼び出された Claude への命令書** である。
Claude Code の hook システムがこのフックを起動したとき、以下の実行契約を順に処理し、
副作用（`ONBOARDING.md` 更新 + `state.json` のタイムスタンプ更新）を完了してから戻ること。

---

## 位置づけ

| 項目 | 値 |
|---|---|
| フック種別 | PostToolUse |
| 対象ツール | `Bash`（test / build / CI 判定系コマンドの完了後）|
| 対象外 | 対象ツール以外（matcher でフィルタ済み、本フックは発火しない） |
| 副作用 1 | `/team-onboarding` 起動による `ONBOARDING.md` 上書き |
| 副作用 2 | `state.json.onboarding.last_refresh` への ISO 8601 タイムスタンプ書き込み |
| 参照元 Issue | #100 |
| 関連フック | `capture-result`（先に動作、無干渉） |
| 関連コマンド | `.claude/claudeos/commands/team-onboarding.md` |
| 関連ループ | `.claude/claudeos/loops/verify-loop.md`（STABLE 判定元） |

---

## 実行契約（呼び出された Claude はこの順で処理すること）

### Step 1: 対象ツール判定とコマンド内容の解析

入力の `tool_name` と `tool_input.command` を確認する。

- `tool_name != "Bash"` → 記録対象外、即座に終了
- `tool_input.command` に以下のパターンが含まれるかを順に判定:
  - `test` / `pytest` / `jest` / `vitest` / `go test` / `cargo test` / `npm test` / `pnpm test`
  - `build` / `tsc` / `webpack` / `vite build` / `cargo build` / `go build` / `npm run build`
  - `lint` / `eslint` / `ruff` / `rubocop` / `clippy`
  - `typecheck` / `mypy` / `pyright` / `tsc --noEmit`
  - `ci` / `gh run` / `gh workflow`
- パターンに一致しない場合 → 対象外、即座に終了

### Step 2: state.json の読み取りと STABLE 判定

```
Read("./state.json")
```

以下のいずれかに該当する場合 → **何もせず終了**（新規プロジェクトで誤作動しない）:

- `state.json` が存在しない
- `state.json.stable` ブロックが欠損
- `state.json.stable.consecutive_success` が閾値未満
- `state.json.stable.target_n` が未定義

STABLE 閾値の既定値:

| 変更規模 | 閾値 (target_n) |
|---|---|
| 小規模（コメント修正・軽微な修正） | 2 |
| 通常（機能追加・バグ修正、既定） | 3 |
| 重要（認証・セキュリティ・DB 変更） | 5 |

`stable.consecutive_success >= stable.target_n` を満たす場合のみ Step 3 へ進む。

### Step 3: レート制限の確認

`state.json.onboarding.last_refresh` を読み取り、現在時刻との差分を計算する。

- `last_refresh` が存在しない → 初回実行として許可、Step 4 へ進む
- 現在時刻 - `last_refresh` < 1 時間（3600 秒） → 多重実行防止のためスキップ、終了
- 現在時刻 - `last_refresh` >= 1 時間 → 許可、Step 4 へ進む

同一セッション内の重複発火を避けるため、メモリ内にセッションロックを設ける:

- セッション中に既に 1 回発火済みならスキップ（`state.json` の変更なしで終了）

### Step 4: `/team-onboarding` の起動

```
Skill("team-onboarding")
```

Skill tool が不可な環境（Copilot CLI / Gemini CLI 等）では以下で代替:

```
Bash("claude /team-onboarding")  # CLI が利用可能な場合のみ
```

上記も不可なら、代替として **ONBOARDING.md を手動更新せず** ログにのみ記録して終了
（フック自体の失敗で session を止めない設計）。

### Step 5: state.json の書き戻し

```
category = "onboarding"
timestamp = 現在時刻（ISO 8601 UTC）

state.json.onboarding.last_refresh = timestamp
state.json.onboarding.refresh_count = (既存値 || 0) + 1
```

書き戻し前に以下を検証:

- JSON として valid か（parse エラーなら abort）
- `onboarding` 以外のブロックが破壊されていないか（diff 確認）

### Step 6: 書き戻し失敗時の挙動

- 書き込みエラー → 標準エラーにログ出力のみ（セッション継続）
- 連続 3 回失敗 → state.json が破損している可能性、フックを一時無効化する旨を警告

---

## 多重実行防止の詳細

本フックは複数レイヤーで多重実行を防止する:

| レイヤー | 条件 | 効果 |
|---|---|---|
| 1. Matcher | `tool_name == "Bash"` かつ特定コマンドパターン | 非対象ツールで発火しない |
| 2. STABLE 未達 | `consecutive_success < target_n` | STABLE 到達前は再生成しない |
| 3. 時間間隔 | `now - last_refresh < 1 時間` | 短期間の連続発火を抑制 |
| 4. セッションロック | 同一セッション内で 1 回のみ | 同セッションの多重呼び出し防止 |
| 5. state.json 不在 | ファイル無し or `stable` ブロック欠損 | 初期化前のプロジェクトで no-op |

---

## state.json スキーマ（本フックが参照・更新するブロック）

```json
{
  "stable": {
    "consecutive_success": 0,
    "target_n": 3,
    "last_verified_at": null
  },
  "onboarding": {
    "last_refresh": null,
    "refresh_count": 0
  }
}
```

### 連携

- `stable.consecutive_success` と `stable.target_n` は `verify-loop.md` が更新する
- `onboarding.last_refresh` は本フックのみが更新する
- `onboarding.refresh_count` は累積メトリクスとして `improve-loop.md` が参照できる

---

## 想定される誤作動と対策

| 誤作動 | 対策 |
|---|---|
| `/team-onboarding` 実行が長時間ブロック | タイムアウト（3 分）超過でフック側から abort し、ログのみ残す |
| state.json が他プロセスと競合 | Write 前に `Read` で最新を取得し merge |
| ONBOARDING.md の一時的な破損（書き込み中断） | `/team-onboarding` 側で `.tmp` ファイル経由の atomic write を実装 |
| STABLE 閾値の過剰再生成（N=2 で毎回発火） | レート制限 1 時間で吸収、それでも多い場合は閾値を N=3 に引き上げ |
| フック自体の hook recursion（ONBOARDING.md 生成が Bash を呼ぶ） | セッションロックで 1 回のみ許可 |

---

## 受入れ基準との対応

Issue #100 の受入れ基準との対応:

| 受入れ基準 | 本フックでの対応箇所 |
|---|---|
| `onboarding-refresh-on-stable.md` が存在する | 本ファイル |
| `hooks.json` に登録されている | `.claude/claudeos/hooks/hooks.json` の `PostToolUse` |
| STABLE 判定時に ONBOARDING.md が更新される | Step 2 + Step 4 |
| 多重実行が抑制される（1 時間 / 1 セッション） | Step 3 + 多重実行防止レイヤー 3-4 |
| state.json 不在環境で no-op | Step 2 + 多重実行防止レイヤー 5 |

---

## 参考

- Issue #100（本フックの実装対象）
- Issue #101/#102（`/team-onboarding` 動的生成方式 — 本フックが呼ぶコマンド）
- `.claude/claudeos/commands/team-onboarding.md`（ONBOARDING.md 生成ロジック）
- `.claude/claudeos/hooks/usage-history-recorder.md`（同じ PostToolUse パターンの先行実装）
- `CLAUDE.md` §5 運用ループ / §9 STABLE 判定
