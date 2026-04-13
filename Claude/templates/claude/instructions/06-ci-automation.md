# CI Manager・GitHub Actions

## 基本原則

- 最大 15 回まで修復試行
- 同一原因 3 回で停止
- 差分なしで停止
- Security blocker 検知で即停止
- 人手承認が必要な操作は実行しない

## CI フロー

1. Push / PR をトリガー
2. Build 実行
3. Test 実行
4. Lint / Format / Static Check
5. Security Check
6. CodeRabbit review 結果確認
7. Codex review 結果確認
8. 失敗時は Issue 自動生成
9. 修復可能なら限定回数で再試行
10. 成功時は STABLE 判定候補へ進行

## GitHub Actions 実装テンプレート

```yaml
name: ClaudeOS CI Manager

on:
  push:
    branches: [main, develop, 'feature/**']
  pull_request:
    branches: [main, develop]
  workflow_dispatch:

jobs:
  build-test-review:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install
        run: |
          if [ -f package-lock.json ]; then npm ci; else npm install; fi

      - name: Lint
        run: npm run lint --if-present

      - name: Test
        run: npm test --if-present

      - name: Build
        run: npm run build --if-present

      - name: Security Audit
        run: npm audit --audit-level=high || true

      - name: Archive logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ci-logs
          path: .

  issue-factory:
    if: failure()
    needs: build-test-review
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Create Failure Report
        run: |
          mkdir -p .claudeos
          echo "CI failed - generate issue" > .claudeos/ci_failure_report.txt

      - name: Upload Failure Report
        uses: actions/upload-artifact@v4
        with:
          name: ci-failure-report
          path: .claudeos/ci_failure_report.txt
```

## Issue Factory + Actions 連携

### 失敗時

- Actions 失敗ログを保存
- 失敗分類を実施
- 重複 Issue を確認
- 未登録なら Issue を生成
- Project を `Blocked` または `Todo` へ更新

### 成功時

- state.json の KPI を更新
- Project を `Verify` または `Done` へ更新
- 成功パターンを learning に保存
