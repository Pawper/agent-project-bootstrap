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
wait_hit=$(stdin_wait_reason "$cmd")
if [ -n "$wait_hit" ]; then
  printf '%s\n' "Blocked \`$wait_hit\` because it reads input that never comes and would hang the shell; give it a file to read, pipe something into it, or use a heredoc (\`cat > file <<'EOF'\`)." >&2
  exit 2
fi
if [ -n "$(worktree_add_reason "$cmd")" ]; then
  printf '%s\n' "Blocked a detached worktree because its commits would be reachable only from that folder; add it with a branch instead, for example \`git worktree add -b task-name path\`." >&2
  exit 2
fi
daemon_hit=$(daemon_stop_reason "$cmd")
if [ -n "$daemon_hit" ]; then
  printf '%s\n' "Blocked \`$daemon_hit\` because the build daemon is shared by every build on this machine, including a self-hosted runner's job in flight, which fails with \"daemon has been stopped\". Let it idle out; stopping what you started means your own servers and watchers, not the daemon. If no runner runs on this machine, prefix the command with DAEMON_STOP_OK=1." >&2
  exit 2
fi
exit 0
