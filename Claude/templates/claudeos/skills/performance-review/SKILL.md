---
name: performance-review
description: "差分や既存コードを **性能観点** でレビューし、ホットスポット・計算量・I/O 回数・ための実務ガイド。"
---

# performance-review

## 概要

差分や既存コードを **性能観点** でレビューし、ホットスポット・計算量・I/O 回数・
並列性・メモリ・DB クエリのリグレッションを検出する skill。

## 使う場面

- Verify フェーズで性能感のある変更を確認したいとき
- DB スキーマ変更 / キャッシュ変更 / 並列処理追加のレビュー
- レイテンシ・スループットの劣化疑い調査
- リリース前最終確認（adversarial review と並走）

## 想定入力

- git diff の差分 / PR 番号
- ホットパスとして指定されたファイル
- ベンチマーク結果（pre/post）が存在すれば

## 期待する出力

`performance-reviewer` agent のフォーマットに従う構造化された指摘:

```
- 重大度: Critical / High / Medium / Low
- 種類: N+1 / Loop I/O / Algorithm / Memory / Concurrency / DB / Cache
- 場所: file:line
- 観測: 現状の問題
- 想定影響: レイテンシ / メモリ / コスト の桁感
- 推奨対策: 最小修正案
- ベンチ要否: yes / no
```

## 標準手順

1. 変更ファイル一覧を git diff から取得
2. ループ・await・query・正規表現の使用箇所を Grep で抽出
3. 計算量とリソース消費の桁感を見積もる
4. ベンチマーク必要性を判定（マイクロベンチ vs e2e）
5. 重大度別に並べて報告
6. Critical/High は必ず修正、Medium は技術的理由付きでスキップ可、Low は任意

## 観点チェックリスト

### コード
- [ ] ループ内 await / blocking I/O
- [ ] N+1 query
- [ ] O(n²) 以上の意図しないネスト
- [ ] hot path の JSON.parse/stringify
- [ ] catastrophic backtracking 正規表現
- [ ] 大規模配列の in-memory 展開

### 並列
- [ ] Promise.all 化できる逐次 await
- [ ] worker pool 上限未設定
- [ ] state file への並列書き込み（race）
- [ ] timeout 不在の API call

### DB
- [ ] index 欠如疑い
- [ ] transaction 長期保持
- [ ] SELECT *
- [ ] bulk INSERT 化可能

### キャッシュ
- [ ] TTL 過短 / 過長
- [ ] キー衝突
- [ ] cache stampede 対策

## 連携

- agent: `performance-reviewer`
- 関連 agent: `code-reviewer` / `database-reviewer`
- 関連 command: `/code-review` / `/codex:adversarial-review`
