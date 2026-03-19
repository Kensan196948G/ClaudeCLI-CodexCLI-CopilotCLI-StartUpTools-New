#!/bin/bash
# ClaudeOS Project Sync — GitHub Projects V2 ステータス自動更新
# Usage: ./project-sync.sh <issue-number> <status>
# Status: Inbox|Backlog|Ready|Design|Development|Verify|DeployGate|Done|Blocked
#
# 前提: gh auth に read:project / project scope が必要
#   gh auth refresh -s read:project,project

set -euo pipefail

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
OWNER="${REPO%%/*}"
ISSUE_NUMBER="${1:?Usage: project-sync.sh <issue-number> <status>}"
STATUS="${2:?Usage: project-sync.sh <issue-number> <status>}"

# ステータス名のバリデーション
VALID_STATUSES="Inbox Backlog Ready Design Development Verify DeployGate Done Blocked"
if ! echo "$VALID_STATUSES" | grep -qw "$STATUS"; then
  echo "ERROR: Invalid status '$STATUS'. Valid: $VALID_STATUSES" >&2
  exit 1
fi

# プロジェクト ID を取得（最初のプロジェクト）
PROJECT_NUMBER=$(gh project list --owner "$OWNER" --format json -q '.[0].number' 2>/dev/null || echo "")
if [ -z "$PROJECT_NUMBER" ]; then
  echo "WARN: No project found for owner $OWNER. Skipping project sync." >&2
  echo "HINT: Run 'gh auth refresh -s read:project,project' to add project scope." >&2
  exit 0
fi

# Issue のプロジェクトアイテム ID を取得
ITEM_ID=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json -q \
  ".items[] | select(.content.number == $ISSUE_NUMBER) | .id" 2>/dev/null || echo "")

if [ -z "$ITEM_ID" ]; then
  echo "INFO: Issue #$ISSUE_NUMBER is not in project $PROJECT_NUMBER. Adding..." >&2
  ITEM_ID=$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "https://github.com/$REPO/issues/$ISSUE_NUMBER" --format json -q '.id' 2>/dev/null || echo "")
  if [ -z "$ITEM_ID" ]; then
    echo "WARN: Failed to add issue to project. Skipping." >&2
    exit 0
  fi
fi

# Status フィールドを更新
gh project item-edit --project-id "$PROJECT_NUMBER" --id "$ITEM_ID" --field-id Status --single-select-option-id "$STATUS" 2>/dev/null || {
  echo "WARN: Failed to update project status. Field ID or option may differ." >&2
  echo "INFO: Manual update needed: Issue #$ISSUE_NUMBER -> $STATUS" >&2
}

echo "OK: Issue #$ISSUE_NUMBER -> $STATUS (Project $PROJECT_NUMBER)"
