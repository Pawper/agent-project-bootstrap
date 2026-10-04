#!/bin/sh
# PreToolUse hook for Bash: refuses the serial merge pattern. The rule it
# enforces: the batch is the unit of merging; serial is the exception you
# name. More than two PRs through merge-queue.sh need --batch or --serial.
here=$(dirname "$0")
. "$here/lib.sh"

input=$(cat)
cmd=$(json_field "$input" command)
[ -n "$cmd" ] || exit 0

hit=$(batch_merge_reason "$cmd")
[ -n "$hit" ] || exit 0

printf '%s\n' "Blocked merging $hit pull requests one at a time because merging must not take longer than the development did; run \`merge-queue.sh --batch PR...\` to merge them in one integration run, or \`--serial\` if these must land alone." >&2
exit 2
