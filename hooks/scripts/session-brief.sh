#!/bin/sh
# SessionStart hook: print the live state of the project in one short block
# so the agent starts from facts, not from notes about the past.
#
# Reads .claude/session-brief.json in the project when present for the
# queue log glob, the memory folder and the line limit. Without it, only
# the git and gh sections print. Every git or gh call fails soft: a missing
# or signed-out tool makes its section say "(unavailable)" and the hook
# still exits 0. Nothing here prints a token, a secret or an environment
# value.
here=$(dirname "$0")
. "$here/lib.sh"
. "$here/session-brief-lib.sh"

input=$(cat)
source=$(json_field "$input" source)
root=${CLAUDE_PROJECT_DIR:-$(json_field "$input" cwd)}
[ -n "$root" ] && [ -d "$root" ] && cd "$root" 2>/dev/null || exit 0

max_lines=40
queue_glob=""
memory_dir=""
config=".claude/session-brief.json"
if [ -f "$config" ]; then
  cfg=$(cat "$config")
  queue_glob=$(json_field "$cfg" queueLogGlob)
  memory_dir=$(json_field "$cfg" memoryDir)
  n=$(json_number "$cfg" maxLines)
  [ -n "$n" ] && max_lines=$n
fi

sections=$(brief_sections "$source")
has() { case " $sections " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# run_bounded COMMAND...: run with a short timeout when one is available.
run_bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 8 "$@"; else "$@"; fi
}

gh_ok=no
if command -v gh >/dev/null 2>&1 && run_bounded gh auth status >/dev/null 2>&1; then gh_ok=yes; fi

out=""
add() { out="$out$1
"; }

# Main
if has main; then
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    log=$(git log --oneline -5 2>/dev/null)
    dirty=$(git status --porcelain 2>/dev/null | head -n 1)
    add "Main:"
    [ -n "$log" ] && add "$log"
    if [ -n "$dirty" ]; then add "The working tree has uncommitted changes."; else add "The working tree is clean."; fi
  else
    add "Main: (unavailable)"
  fi
fi

# Open pull requests
if has prs; then
  if [ "$gh_ok" = yes ]; then
    prs=$(run_bounded gh pr list --limit 10 --json number,title,mergeable,statusCheckRollup --jq '
      .[] | [
        .number, .title, .mergeable,
        ([.statusCheckRollup[]? | select(.conclusion == "SUCCESS" or .state == "SUCCESS")] | length),
        ([.statusCheckRollup[]? | select((.conclusion // "") | test("FAILURE|TIMED_OUT|CANCELLED|ACTION_REQUIRED")) ] | length)
          + ([.statusCheckRollup[]? | select((.state // "") | test("FAILURE|ERROR"))] | length),
        ([.statusCheckRollup[]? | select((.conclusion == null or .conclusion == "") and (.state == null or .state == "PENDING" or .state == "EXPECTED"))] | length)
      ] | @tsv' 2>/dev/null) || prs=""
    if [ -n "$prs" ]; then
      lines=$(printf '%s\n' "$prs" | while IFS= read -r line; do [ -n "$line" ] && pr_line "$line"; done)
      add "Open pull requests:"
      add "$lines"
    fi
  else
    add "Open pull requests: (unavailable)"
  fi
fi

# Queue
if has queue && [ -n "$queue_glob" ]; then
  set -f; set +f
  newest=""; newest_m=0
  for f in $queue_glob; do
    [ -f "$f" ] || continue
    m=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    [ "$m" -gt "$newest_m" ] && { newest_m=$m; newest=$f; }
  done
  if [ -n "$newest" ]; then
    now=$(date +%s)
    if [ "$(log_is_recent "$newest_m" "$now")" = yes ]; then
      add "Queue: ran in the last two hours. Last line: $(tail -n 1 "$newest" 2>/dev/null)"
    else
      add "Queue: no run in the last two hours."
    fi
  fi
fi

# In progress
if has inprogress; then
  if [ "$gh_ok" = yes ]; then
    ip=$( { run_bounded gh issue list --label "state:in-progress" --limit 10 --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null;
           run_bounded gh issue list --label "state: in progress" --limit 10 --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null; } | awk '!seen[$0]++')
    if [ -n "$ip" ]; then add "In progress:"; add "$(trim_section "$ip" 10)"; fi
  else
    add "In progress: (unavailable)"
  fi
fi

# Last handoff
if has handoff && [ -n "$memory_dir" ] && [ -d "$memory_dir" ]; then
  listing=$(for f in "$memory_dir"/handoff-*; do
    [ -f "$f" ] || continue
    m=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    printf '%s\t%s\n' "$m" "$f"
  done)
  pick=$(newest_handoff "$listing")
  if [ -n "$pick" ]; then
    add "Last handoff ($(basename "$pick")):"
    add "$(handoff_head "$(cat "$pick")" 2)"
  fi
fi

# Owner actions waiting
if has owner; then
  if [ "$gh_ok" = yes ]; then
    wo=$( { run_bounded gh issue list --label "state:waiting-on-owner" --limit 5 --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null;
           run_bounded gh issue list --label "state: waiting on owner" --limit 5 --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null; } | awk '!seen[$0]++')
    if [ -n "$wo" ]; then add "Owner actions waiting:"; add "$(trim_section "$wo" 5)"; fi
  else
    add "Owner actions waiting: (unavailable)"
  fi
fi

trim_section "$(printf '%s' "$out")" "$max_lines"
exit 0
