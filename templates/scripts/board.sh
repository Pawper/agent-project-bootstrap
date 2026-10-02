#!/bin/sh
# Create the project board with its State field and the matching labels,
# exactly as section 6 of the skill says.
# Usage: sh scripts/board.sh OWNER OWNER/REPO [TITLE]
# Needs gh signed in with the project scope: gh auth refresh -s project
#
# After it runs, open the board's Workflows tab and switch on the four
# built-in workflows listed in the README. The API cannot do that part.
set -e
owner=$1
repo=$2
title=${3:-$(basename "$repo")}
[ -n "$owner" ] && [ -n "$repo" ] || { echo "Usage: sh scripts/board.sh OWNER OWNER/REPO [TITLE]" >&2; exit 2; }

here=$(dirname "$0")
sh "$here/labels.sh"

number=$(gh project create --owner "$owner" --title "$title" --format json --jq .number)
echo "project $number: $title"

gh project field-create "$number" --owner "$owner" --name State --data-type SINGLE_SELECT \
  --single-select-options "Ready,In progress,Waiting on owner,Waiting on a service,Parked,Dated,After launch" >/dev/null
echo "field State with seven values"

gh project link "$number" --owner "$owner" --repo "$repo" >/dev/null
echo "linked to $repo"

cat <<EOF

Done. Two things are left to do by hand:
1. Open the board, choose the Workflows tab, and switch on the four built-in workflows listed in the README.
2. Set the board view to group by State. That view is the status report.

To set State on a new issue from a script: sh scripts/state.sh $number $owner ISSUE_NUMBER "Ready"
EOF
