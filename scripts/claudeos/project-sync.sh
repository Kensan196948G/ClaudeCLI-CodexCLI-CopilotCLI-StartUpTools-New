#!/bin/bash
# ClaudeOS Project Sync - GitHub Projects V2 status automation
# Usage: ./project-sync.sh <issue-number> <status> [project-number]
# Status: Inbox|Backlog|Ready|Design|Development|Verify|DeployGate|Done|Blocked
#
# Requires GitHub project scopes:
#   gh auth refresh -s read:project,project

set -euo pipefail

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
OWNER="${REPO%%/*}"
ISSUE_NUMBER="${1:?Usage: project-sync.sh <issue-number> <status> [project-number]}"
STATUS="${2:?Usage: project-sync.sh <issue-number> <status> [project-number]}"
PROJECT_NUMBER_INPUT="${3:-}"

VALID_STATUSES="Inbox Backlog Ready Design Development Verify DeployGate Done Blocked"
if ! echo "$VALID_STATUSES" | grep -qw "$STATUS"; then
  echo "ERROR: Invalid status '$STATUS'. Valid: $VALID_STATUSES" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "WARN: jq is required to resolve GitHub Projects field IDs. Skipping project sync." >&2
  exit 0
fi

if [ -n "$PROJECT_NUMBER_INPUT" ]; then
  PROJECT_NUMBER="$PROJECT_NUMBER_INPUT"
else
  PROJECT_NUMBER="$(gh project list --owner "$OWNER" --format json -q '.[0].number' 2>/dev/null || echo "")"
fi

if [ -z "$PROJECT_NUMBER" ]; then
  echo "WARN: No project found for owner $OWNER. Skipping project sync." >&2
  echo "HINT: Run 'gh auth refresh -s read:project,project' to add project scope." >&2
  exit 0
fi

PROJECT_JSON="$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json 2>/dev/null || echo "")"
if [ -z "$PROJECT_JSON" ]; then
  echo "WARN: Failed to load project metadata for project $PROJECT_NUMBER." >&2
  exit 0
fi

PROJECT_ID="$(printf '%s' "$PROJECT_JSON" | jq -r '.id // empty')"
STATUS_FIELD_ID="$(printf '%s' "$PROJECT_JSON" | jq -r '.fields[]? | select(.name == "Status") | .id // empty' | head -n 1)"
STATUS_OPTION_ID="$(printf '%s' "$PROJECT_JSON" | jq -r --arg status "$STATUS" '.fields[]? | select(.name == "Status") | .options[]? | select(.name == $status) | .id // empty' | head -n 1)"
if [ -z "$PROJECT_ID" ] || [ -z "$STATUS_FIELD_ID" ] || [ -z "$STATUS_OPTION_ID" ]; then
  echo "WARN: Failed to resolve Status field metadata for project $PROJECT_NUMBER." >&2
  echo "INFO: Manual update needed: Issue #$ISSUE_NUMBER -> $STATUS" >&2
  exit 0
fi

ISSUE_URL="https://github.com/$REPO/issues/$ISSUE_NUMBER"
ITEM_ID="$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json -q \
  ".items[] | select(.content.number == $ISSUE_NUMBER) | .id" 2>/dev/null || echo "")"

if [ -z "$ITEM_ID" ]; then
  echo "INFO: Issue #$ISSUE_NUMBER is not in project $PROJECT_NUMBER. Adding..." >&2
  ITEM_ID="$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$ISSUE_URL" --format json -q '.id' 2>/dev/null || echo "")"
  if [ -z "$ITEM_ID" ]; then
    echo "WARN: Failed to add issue to project. Skipping." >&2
    exit 0
  fi
fi

if ! gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id "$STATUS_FIELD_ID" --single-select-option-id "$STATUS_OPTION_ID" >/dev/null 2>&1; then
  echo "WARN: Failed to update project status via GitHub CLI." >&2
  echo "INFO: Manual update needed: Issue #$ISSUE_NUMBER -> $STATUS" >&2
  exit 0
fi

echo "OK: Issue #$ISSUE_NUMBER -> $STATUS (Project $PROJECT_NUMBER)"
