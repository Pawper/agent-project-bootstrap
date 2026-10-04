#!/bin/sh
# Create or adopt the project board, add its State field and the matching
# labels, exactly as section 5 of the skill says.
# Usage: sh scripts/board.sh OWNER OWNER/REPO [TITLE]
#        sh scripts/board.sh OWNER OWNER/REPO --existing NUMBER
# Needs gh signed in with the project scope: gh auth refresh -s project
#
# With --existing, no new project is created: the State field is added to
# the board you name if it is not there yet, and the repository is linked.
# After it runs, open the board's Workflows tab and switch on the four
# built-in workflows listed in the README. The API cannot do that part.
set -e
owner=$1
repo=$2
[ -n "$owner" ] && [ -n "$repo" ] || { echo "Usage: sh scripts/board.sh OWNER OWNER/REPO [TITLE | --existing NUMBER]" >&2; exit 2; }

here=$(dirname "$0")
sh "$here/labels.sh"

if [ "$3" = "--existing" ]; then
  number=$4
  [ -n "$number" ] || { echo "--existing needs the project number." >&2; exit 2; }
  echo "using existing project $number"
else
  title=${3:-$(basename "$repo")}
  number=$(gh project create --owner "$owner" --title "$title" --format json --jq .number)
  echo "project $number: $title"
fi

has_state=$(gh project field-list "$number" --owner "$owner" --format json --jq '[.fields[] | select(.name == "State")] | length')
if [ "$has_state" = "0" ]; then
  gh project field-create "$number" --owner "$owner" --name State --data-type SINGLE_SELECT \
    --single-select-options "Ready,In progress,Waiting on owner,Waiting on a service,Parked,Dated,After launch,Blocked" >/dev/null
  echo "field State with eight values"
else
  echo "field State is already there; check it has the eight values, including Blocked"
fi

gh project link "$number" --owner "$owner" --repo "$repo" >/dev/null 2>&1 || true
echo "linked to $repo"

cat <<EOF

Done. Two things are left to do by hand:
1. Open the board, choose the Workflows tab, and switch on the four built-in workflows listed in the README.
2. Set the board view to group by State. That view is the status report.

To set State on a new issue from a script: sh scripts/state.sh $number $owner ISSUE_NUMBER "Ready"
EOF
