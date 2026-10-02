#!/bin/sh
# Set the State field on the board for one issue. The coordinator runs this
# right after filing, so the board never waits for a hand update.
# Usage: sh scripts/state.sh PROJECT_NUMBER OWNER ISSUE_NUMBER "Ready"
# Needs gh signed in with the project scope: gh auth refresh -s project
set -e
project=$1
owner=$2
issue=$3
state=$4
[ -n "$project" ] && [ -n "$owner" ] && [ -n "$issue" ] && [ -n "$state" ] || {
  echo 'Usage: sh scripts/state.sh PROJECT_NUMBER OWNER ISSUE_NUMBER "Ready"' >&2; exit 2; }

project_id=$(gh project view "$project" --owner "$owner" --format json --jq .id)
field_id=$(gh project field-list "$project" --owner "$owner" --format json \
  --jq '.fields[] | select(.name == "State") | .id')
option_id=$(gh project field-list "$project" --owner "$owner" --format json \
  --jq ".fields[] | select(.name == \"State\") | .options[] | select(.name == \"$state\") | .id")
[ -n "$field_id" ] && [ -n "$option_id" ] || {
  echo "Could not find the State field or the value \"$state\" on project $project." >&2; exit 1; }

issue_url=$(gh issue view "$issue" --json url --jq .url)
item_id=$(gh project item-list "$project" --owner "$owner" --limit 1000 --format json \
  --jq ".items[] | select(.content.url == \"$issue_url\") | .id")
if [ -z "$item_id" ]; then
  item_id=$(gh project item-add "$project" --owner "$owner" --url "$issue_url" --format json --jq .id)
fi

gh project item-edit --project-id "$project_id" --id "$item_id" \
  --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null
echo "issue $issue: State = $state"
