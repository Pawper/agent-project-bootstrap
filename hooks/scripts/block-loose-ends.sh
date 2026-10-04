#!/bin/sh
# PreToolUse hook for Bash: refuses two ways of leaving work with no ending.
#   - gh pr close with no comment: a closed pull request must say why, or
#     what replaced it.
#   - git worktree add --detach: commits made on a detached HEAD are
#     reachable only from that folder; always create a branch.
here=$(dirname "$0")
. "$here/lib.sh"
. "$here/worktree-lib.sh"

input=$(cat)
cmd=$(json_field "$input" command)
[ -n "$cmd" ] || exit 0

if [ -n "$(pr_close_reason "$cmd")" ]; then
  printf '%s\n' "Blocked \`gh pr close\` because a closed pull request needs an ending; add \`--comment\` saying why or what replaced it, or run \`sh scripts/worktrees.sh close PR \"reason\"\`, which also archives the branch and removes its worktree." >&2
  exit 2
fi
if [ -n "$(worktree_add_reason "$cmd")" ]; then
  printf '%s\n' "Blocked a detached worktree because its commits would be reachable only from that folder; add it with a branch instead, for example \`git worktree add -b task-name path\`." >&2
  exit 2
fi
exit 0
