# ClaudeOS Evaluation Methodology v1.0

_Source of truth for evaluation reports produced against this repository._

## 背景

2026-04-11、ClaudeOS v7.4 CLAUDE.md に対する外部評価レポートが「5 時間タイムボックスという思想的一貫性」を ★14 つよみとして加点したが、独立検証の結果 **時間管理ロジックは完全未実装**（state.json 固定値 / hook スタブ / 閾値分岐コード無し）であることが判明した。評価の符号が逆向きだった。同じレポートは `mcp-configs/` ディレクトリ配下の vercel.json・railway.json への言及を 2 箇所で行ったが、**そのディレクトリ自体が存在しなかった**。

これらの誤認は評価者の怠慢ではなく、**評価プロトコルの欠落** から生じた構造的な問題である。本ドキュメントはこの事件を founding case とし、同種の符号逆転と虚構 claim を構造的に防ぐことを目的とする。

---

## 1. 必須ヘッダーテンプレート

すべての評価レポートは以下のヘッダーで開始すること。

```markdown
# <リポジトリ名> 評価レポート

| 項目 | 値 |
|---|---|
| 評価実施日時 | YYYY-MM-DDTHH:MM:SS+09:00 |
| 対象 commit | <git rev-parse HEAD 7 桁> |
| 対象 branch | <branch name> |
| 評価者 | <human / model name> |
| 評価所要時間 | <minutes> |
| confidence | <0-100%> |
```

`評価所要時間 < 10 分` かつ `confidence > 80%` は red flag。深掘り不足の疑い。

---

## 2. Claim Classification — Runtime Assertion Badges

すべての主張には以下 4 段階のバッジを **必須** で付与する。

| バッジ | 意味 | 検証方法 | 例 |
|---|---|---|---|
| `[doc-only]` | 文書に書いてあるだけ | Read / Grep | 「CLAUDE.md に 5h 上限と記載」 |
| `[file-exists]` | 該当ファイル/ディレクトリが存在する | Glob / ls | 「session-start.js が存在する」 |
| `[code-reachable]` | コード中の関数定義を目視確認 | Read + 行番号 | 「session-start.js:12 に wallClockStart 算出ロジック」 |
| `[runtime-verified]` | 実際に実行して期待動作を確認 | Bash で実行＋出力 check | 「hook 実行で anchor ファイルが生成された」 |

**原則**: 「〜が実装されている」「〜が動作する」「〜が連動している」という表現は `[code-reachable]` 以上のバッジを持つ claim にのみ使用可。`[doc-only]` や `[file-exists]` では「〜と記載されている」「〜のファイルが存在する」に言い換える。

---

## 3. Fact-Check Checklist（評価提出前に必須実行）

評価レポート submit 前に以下を全項目チェックする。

- [ ] すべての言及ファイル名を `Glob` または `ls` で実在確認した
- [ ] すべての言及ディレクトリを `ls` で実在確認した
- [ ] 「XX が存在している」という claim 全てに evidence (`file_path:line`) を付与した
- [ ] hook / script / 実行コードへの言及は `[code-reachable]` 以上のバッジを付与した
- [ ] 「動作している」「連動している」「実装されている」という表現を使用した claim は `[runtime-verified]` で裏付けた、あるいは「動作すると記載されている」に書き換えた
- [ ] 「同じ数値が N 箇所に書かれている」を integration の根拠に使っていない（コピペと実装連動は別概念）
- [ ] 未検証項目を末尾 Limitations セクションに全列挙した
- [ ] つよみ全項目に Challenge Protocol (§6) を適用した
- [ ] 情報源に §4 の分類タグを付与した

**1 つでも未チェックなら提出不可**。

---

## 4. 情報源信頼度分類

すべての参考文献に以下タグを付与する。

| タグ | ドメイン例 | 信頼度 | 採用条件 |
|---|---|---|---|
| `[official]` | `docs.anthropic.com`, `code.claude.com`, `console.anthropic.com` | 🟢 高 | 単独で evidence として採用可 |
| `[github-official]` | `github.com/anthropics/*` | 🟢 高 | 単独で採用可 |
| `[third-party-blog]` | 個人/企業 blog（mindstudio.ai, apiyi.com, smart-webtech.com 等） | 🔴 低 | 公式と併記必須。単独 claim の根拠には不可 |
| `[unknown]` | 上記いずれでもない | ⚪ 不明 | 別途検証。未検証なら Limitations 送り |

**2026 年以降の Claude Code 新機能 claim** に `[third-party-blog]` 単独出典を使用するのは禁止。最低 1 本の `[official]` または `[github-official]` と併記する。

---

## 5. Scoring Methodology — 透明性の原則

### 5.1 計算式（固定）

```
score = (axis1 + axis2 + axis3 + axis4 + axis5 + axis6) × 20 ÷ 6
```

各軸は 0-5 星（整数）。1 星 = 20 点基準。評価軸は次の 6 軸を標準とする（追加は可、削除は不可）。

### 5.2 必須 6 軸

1. **事実整合性（file-level）** — 言及したファイル/ディレクトリの実在率
2. **実装整合性（code-level）** — `[code-reachable]` 以上の claim 比率
3. **論理整合性** — 内部矛盾の有無（役割表 vs 起動順表など）
4. **網羅性** — 評価対象領域のカバー率
5. **可読性** — 構造・誤字・記法の品質
6. **自己批判性** — limitations と未検証項目の明示度

### 5.3 開示義務

各軸の得点と、それぞれの減点理由・加点理由を本文中に **明記** する。総合点のみの提示は不可。

### 5.4 confidence interval

最終スコアは必ず `X/100 ± N` 形式で提示する。N は以下基準で決める。

| 検証深度 | N |
|---|---|
| 全項目 `[runtime-verified]` | ±2 |
| 80% 以上が `[code-reachable]` 以上 | ±4 |
| 50-80% が `[code-reachable]` 以上 | ±6 |
| それ未満 | ±10 |

---

## 6. Challenge-the-Strength Protocol

各「つよみ」項目を書き終えたら、提出前に以下を自問する。

1. この「強み」は、実行時に動作する機構によって担保されているか？
2. もしそれを担保するコードをリポジトリから削除した場合、何らかの自動テストが失敗するか？
3. 同じ内容が複数ファイルに書かれているだけではないか？（ドキュメントのコピペは integration ではない）
4. 根拠の最下層に到達したとき、それは `[doc-only]` で終わっていないか？

**判定**:
- (1)(2)(4) のいずれかに明確な Yes が無い場合 → この項目は **つよみから除外** し、場合によっては **よわみに移動** する
- (3) が Yes の場合 → 「文書的一貫性」と明記し、実装連動を主張しない

### 6.1 反例ケーススタディ（2026-04-11）

| 主張 | Challenge | 結論 |
|---|---|---|
| 「5h タイムボックスが CLAUDE.md / state.json / loop-guard.md で同じ 300 分と記載され思想的に一貫」 | (1) No（強制装置無し） / (2) No（テスト無し） / (3) Yes（コピペ） | **つよみ不成立 → よわみ最上位に移動** |
| 「Token 配分 70/85/95% 閾値が token-budget.md と state.json 両方にある」 | (1) 未検証 / (2) 未検証 | **つよみ留保 → Limitations 送り** |

---

## 7. Limitations Section（必須末尾章）

すべての評価レポートは以下 4 項目を含む末尾章を持つ。

```markdown
## Limitations

### 7.1 検証できなかった項目
- <項目 1>（理由: <なぜ検証できなかったか>）
- <項目 2>
- ...

### 7.2 confidence interval
総合評価 X/100 ± N。N の根拠: <検証深度分類>

### 7.3 評価者が自認する盲点
- <ドメイン知識の不足>
- <使用ツールの制約>
- <時間的制約>

### 7.4 次回評価で補強すべき点
- <具体的な追加検証タスク>
```

Limitations セクションの欠如 = 評価レポートとして **不受理**。

---

## 8. Radar Chart Template（推奨）

6 軸評価を視覚化する際は mermaid または ascii radar で以下のように記述。

```text
          事実整合性
              ★★★★
論理整合性  ★★★    ★★    実装整合性
          ★★        ★★
              ★★
          ★★★★
          自己批判性
          (等々、6 軸すべて)
```

mermaid 例:
```mermaid
%%{init: {"quadrantChart": {"chartWidth": 400}}}%%
quadrantChart
    title 評価軸別スコア
    x-axis Low --> High
    y-axis Low --> High
    quadrant-1 High priority
    ...
```

---

## 9. Codex Plugin Smoke-Test 義務

評価対象リポジトリが CLAUDE.md で `/codex:review` や `/codex:rescue` を「必須」と定義している場合、評価者は次の手順で **実動作確認** を行う。

```powershell
# scripts/eval/codex-smoke-test.ps1 を実行
pwsh .\scripts\eval\codex-smoke-test.ps1
```

結果を `.claude/claudeos/system/codex-availability.json` に保存し、評価本文に引用する。skill 未登録・コマンド不在の場合は「Codex 必須規約が実行不能環境で書かれている」として **よわみに計上** する。

---

## 10. Fact-Check Harness 運用

`scripts/eval/fact-check.ps1` に claim リスト（yaml または json）を渡すと、言及ファイル/ディレクトリを自動検証する。

```yaml
# sample claim list
- type: file
  path: .claude/claudeos/system/orchestrator.md
- type: dir
  path: mcp-configs/
- type: file_with_content
  path: .github/workflows/ci.yml
  must_contain: "Pester"
```

fact-check harness の出力を評価本文に引用することで、「mcp-configs/ 虚構事件」型の誤認を構造的に防ぐ。

---

## 11. 適用範囲

本メソドロジーは以下に適用する。

- `.claude/claudeos/` 配下ドキュメントに対する評価
- プロジェクト CLAUDE.md に対する評価
- README.md 等利用者向け文書に対する評価
- Codex 出力の評価（ただし `/codex:review` の本体ロジックには適用せず、その出力のメタ評価にのみ適用）

適用外：

- 個別 PR の code review（既存の `/codex:review` 系で代替）
- セキュリティ監査（専用プロトコル別途）

---

## 12. Appendix A — 2026-04-11 Case Study

**事件名**: ClaudeOS v7.4 CLAUDE.md Evaluation Sign-Flip Incident

**概要**:
外部評価レポートが ClaudeOS v7.4 に対し 74/100 (★★★★☆) を与えたが、独立検証の結果以下 3 つの根本的誤認が発覚した。

### 誤認 1: 5h タイマー符号逆転
- 評価: 「★14 思想的一貫性」として加点
- 実態: state.json 固定値 / session-start.js スタブ / 閾値分岐コード無し
- 発覚: Explore agent による runtime 検証
- 教訓: 「同じ数値が N 箇所にある」はコピペの証拠であって integration の根拠ではない

### 誤認 2: mcp-configs/ 虚構参照
- 評価: 「mcp-configs/vercel.json・railway.json を活用していない」としてよわみ追加
- 実態: `mcp-configs/` ディレクトリ自体が存在しない（`ls: No such file or directory`）
- 発覚: `ls -la mcp-configs/` 実行
- 教訓: ファイルを参照する前に `ls` 1 回で済む実在確認を飛ばさない

### 誤認 3: CI テンプレート前提齟齬
- 評価: CLAUDE.md の「npm ci / npm test / npm audit」テンプレートをそのまま受容
- 実態: `.github/workflows/ci.yml` は windows-latest + PowerShell + Pester（307 tests）
- 発覚: `.github/workflows/ci.yml` 先頭 60 行を Read
- 教訓: 規約文書と実装の前提齟齬は最大級のよわみ

### 修復

本メソドロジー (v1.0) の制定、および以下実装:

- `.claude/claudeos/scripts/hooks/session-start.js` — 実装化（45 行）
- `.claude/settings.json` — SessionStart hook 登録
- `.claude/session-anchor.json` — immutable anchor（.gitignore 済）
- CronCreate one-shot (`53f81dad`) — 5h 物理割り込み

これらは `feat(hooks): 5時間タイマー 3層防御を実装 (SessionStart anchor)` として commit `f8b25b4` で反映。

---

## Revision History

| version | date | author | change |
|---|---|---|---|
| v1.0 | 2026-04-11 | Claude Opus 4.6 (CTO delegation) | 初版制定。Sign-Flip Incident を受けて策定 |
