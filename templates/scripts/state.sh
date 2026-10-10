#!/bin/sh
# Set an issue's state in one go: the state label, the board's State field,
# and the mirrored built-in Status. Use it when filing and whenever the
# state changes, so the three never disagree.
# Usage: sh scripts/state.sh PROJECT_NUMBER OWNER ISSUE_NUMBER "Ready"
# Needs gh signed in with the project scope: gh auth refresh -s project
set -e
project=$1
owner=$2
issue=$3
state=$4
[ -n "$project" ] && [ -n "$owner" ] && [ -n "$issue" ] && [ -n "$state" ] || {
  echo 'Usage: sh scripts/state.sh PROJECT_NUMBER OWNER ISSUE_NUMBER "Ready"' >&2; exit 2; }

here=$(dirname "$0")
. "$here/board-lib.sh"

board_load "$project" "$owner"
closed=$(gh api "repos/{owner}/{repo}/issues/$issue" --jq '.state == "closed"')
board_apply "$issue" "$state" "$closed"
