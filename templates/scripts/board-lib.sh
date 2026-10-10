#!/bin/sh
# Shared gh calls for the board scripts. Sourced by state.sh and
# board-sync.sh. The pure mappings live in scripts/ci/lib.sh.
# Needs gh signed in with the project scope: gh auth refresh -s project

here_lib=$(dirname "$0")
. "$here_lib/ci/lib.sh"

ALL_STATE_LABELS="state:ready state:in-progress state:waiting-on-owner state:waiting-on-service state:parked state:dated state:after-launch state:blocked"

# board_load PROJECT OWNER
# Reads the ids the other functions need into BOARD_* variables.
board_load() {
  BOARD_NUMBER=$1
  BOARD_OWNER=$2
  BOARD_ID=$(gh project view "$1" --owner "$2" --format json --jq .id)
  BOARD_STATE_FIELD=$(board_fields '.fields[] | select(.name == "State") | .id')
  BOARD_STATUS_FIELD=$(board_fields '.fields[] | select(.name == "Status") | .id')
  [ -n "$BOARD_STATE_FIELD" ] || { echo "Project $1 has no State field; run sh scripts/board.sh first." >&2; exit 1; }
}

# board_fields FILTER: the field list through gh's built-in jq, so nothing
# beyond gh itself is needed.
board_fields() {
  gh project field-list "$BOARD_NUMBER" --owner "$BOARD_OWNER" --format json --jq "$1"
}

# board_option FIELD_ID NAME -> option id, case-insensitive on the name
board_option() {
  board_fields ".fields[] | select(.id == \"$1\") | .options[] | select((.name | ascii_downcase) == (\"$2\" | ascii_downcase)) | .id"
}

# board_item_for ISSUE_URL -> item id, adding the issue to the board if needed
board_item_for() {
  item=$(gh project item-list "$BOARD_NUMBER" --owner "$BOARD_OWNER" --limit 1000 --format json \
    --jq ".items[] | select(.content.url == \"$1\") | .id")
  if [ -z "$item" ]; then
    item=$(gh project item-add "$BOARD_NUMBER" --owner "$BOARD_OWNER" --url "$1" --format json --jq .id)
  fi
  printf '%s\n' "$item"
}

# board_set_field ITEM FIELD_ID OPTION_ID
board_set_field() {
  gh project item-edit --project-id "$BOARD_ID" --id "$1" --field-id "$2" --single-select-option-id "$3" >/dev/null
}

# issue_set_state_label ISSUE LABEL: add this state label, remove the others
issue_set_state_label() {
  remove=""
  for l in $ALL_STATE_LABELS; do [ "$l" = "$2" ] || remove="$remove --remove-label $l"; done
  gh issue edit "$1" --add-label "$2" $remove >/dev/null
}

# board_apply ISSUE_NUMBER STATE_NAME CLOSED
# Set the label, the State field and the mirrored Status for one issue.
board_apply() {
  ba_issue=$1
  ba_state=$2
  ba_closed=$3
  ba_label=$(label_from_state_name "$ba_state")
  ba_status=$(status_for "$ba_state" "$ba_closed")
  ba_state_opt=$(board_option "$BOARD_STATE_FIELD" "$ba_state")
  [ -n "$ba_state_opt" ] || { echo "The State field has no value \"$ba_state\"." >&2; return 1; }
  ba_url=$(gh api "repos/{owner}/{repo}/issues/$ba_issue" --jq .html_url)
  ba_item=$(board_item_for "$ba_url")
  issue_set_state_label "$ba_issue" "$ba_label"
  board_set_field "$ba_item" "$BOARD_STATE_FIELD" "$ba_state_opt"
  if [ -n "$BOARD_STATUS_FIELD" ]; then
    ba_status_opt=$(board_option "$BOARD_STATUS_FIELD" "$ba_status")
    [ -n "$ba_status_opt" ] && board_set_field "$ba_item" "$BOARD_STATUS_FIELD" "$ba_status_opt"
  fi
  echo "issue $ba_issue: $ba_label, State = $ba_state, Status = $ba_status"
}
