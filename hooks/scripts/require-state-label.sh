#!/bin/sh
# PreToolUse hook for Bash: refuses `gh issue create` without a State label.
# The rule it enforces: every issue carries its state from the moment it is
# filed, so the board and the audits can trust the label.
here=$(dirname "$0")
. "$here/lib.sh"

input=$(cat)
cmd=$(json_field "$input" command)
[ -n "$cmd" ] || exit 0

hit=$(state_label_reason "$cmd")
[ -n "$hit" ] || exit 0

printf '%s\n' "Blocked \`$hit\` because every issue needs a State label at filing; add \`--label state:ready\` (or state:waiting-on-owner, state:waiting-on-service, state:parked, state:dated) and run it again." >&2
exit 2
