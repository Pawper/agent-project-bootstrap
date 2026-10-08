#!/bin/sh
# Pure helpers for the merge queue's batch mode. Nothing here calls git or
# gh, so every function is tested with strings in tests/run.sh.

# batch_order ARGS...
# Print the PR numbers in the order given, one per line, with repeats
# dropped and anything that is not a number ignored.
batch_order() {
  seen=" "
  for bo_a in "$@"; do
    case "$bo_a" in ''|*[!0-9]*) continue ;; esac
    case "$seen" in *" $bo_a "*) continue ;; esac
    seen="$seen$bo_a "
    printf '%s\n' "$bo_a"
  done
}

# tests_for_diff PATHS
# PATHS is one changed path per line. Print the unit and component test
# files among them, one per line: anything under tests/ or ending in
# .test.* or .spec.* with a JavaScript or TypeScript extension. Browser
# runs (anything under e2e/, playwright/ or cypress/) are left out; the one
# full CI run covers those.
tests_for_diff() {
  printf '%s\n' "$1" | tr -d '\r' | tr '\\' '/' | awk '
    /^(e2e|playwright|cypress)\// { next }
    /\/(e2e|playwright|cypress)\// { next }
    /\.(test|spec)\.(js|jsx|ts|tsx|mjs|cjs|mts|cts)$/ { print; next }
    /^tests?\/.*\.(js|jsx|ts|tsx|mjs|cjs|mts|cts)$/ { print }
  ' | awk '!seen[$0]++'
}

# batch_branch_name DATE [N]
# "batch-2026-10-03", or "batch-2026-10-03-2" for the second batch of a day.
batch_branch_name() {
  if [ -n "$2" ] && [ "$2" -gt 1 ] 2>/dev/null; then
    printf 'batch-%s-%s\n' "$1" "$2"
  else
    printf 'batch-%s\n' "$1"
  fi
}

# batch_pr_body CARRIED
# CARRIED is one line per merged PR: "NUMBER<TAB>TITLE". Print the body of
# the batch PR: one line per carried PR with its Closes line, so merging the
# batch closes each PR's issue and the originals show as merged.
batch_pr_body() {
  printf 'One integration run for the pull requests below, merged in this order with merge commits. Each keeps its own history; the full suite runs once here.\n\n'
  printf '%s\n' "$1" | awk -F'\t' 'NF >= 1 && $1 != "" { printf "- #%s %s. Closes #%s\n", $1, $2, $1 }'
}

# batch_line NUMBER OUTCOME [WHY]
# The one line printed per PR: "#12 merged into the batch", "#13 dropped:
# conflicts with main", "#14 merged serially".
batch_line() {
  if [ -n "$3" ]; then
    printf '#%s %s: %s\n' "$1" "$2" "$3"
  else
    printf '#%s %s\n' "$1" "$2"
  fi
}

# drain_candidates LIST BASE [TRIED]
# LIST is one open pull request per line:
#   "NUMBER<TAB>DRAFT(true|false)<TAB>MERGEABLE<TAB>ROLLUP<TAB>BASE_BRANCH"
# where ROLLUP is green, red, pending or none. Print, one per line in
# number order, the pull requests the drain should merge this round: not a
# draft, aimed at BASE, not conflicting, green, and not in TRIED (numbers a
# previous round already tried and could not merge).
drain_candidates() {
  printf '%s\n' "$1" | tr -d '\r' | awk -F'\t' -v base="$2" -v tried=" $3 " '
    NF >= 5 && $2 == "false" && $5 == base && toupper($3) != "CONFLICTING" && $4 == "green" && index(tried, " " $1 " ") == 0 { print $1 }' | sort -n
}

# drain_waiting LIST BASE
# How many non-draft pull requests aimed at BASE are still running CI.
drain_waiting() {
  printf '%s\n' "$1" | tr -d '\r' | awk -F'\t' -v base="$2" '
    NF >= 5 && $2 == "false" && $5 == base && $4 == "pending" { n++ } END { print n + 0 }'
}

# drain_retry LIST BASE RETRIED
# The red pull requests (not drafts, aimed at BASE) whose failed run has
# not been re-run yet in this drain: one retry each, because a flaky test
# or a lost runner should not stop a change.
drain_retry() {
  printf '%s\n' "$1" | tr -d '\r' | awk -F'\t' -v base="$2" -v tried=" $3 " '
    NF >= 5 && $2 == "false" && $5 == base && $4 == "red" && index(tried, " " $1 " ") == 0 { print $1 }' | sort -n
}

# drain_attention LIST BASE RETRIED
# The pull requests a person or an agent must look at, one per line as
# "NUMBER<TAB>why": conflicting with the base, or red again after its one
# retry. The drain exits non-zero naming these, so nobody has to notice.
drain_attention() {
  printf '%s\n' "$1" | tr -d '\r' | awk -F'\t' -v base="$2" -v tried=" $3 " '
    NF >= 5 && $2 == "false" && $5 == base {
      if (toupper($3) == "CONFLICTING") printf "%s\thas conflicts with %s\n", $1, base
      else if ($4 == "red" && index(tried, " " $1 " ") > 0) printf "%s\tfailed CI twice\n", $1
    }' | sort -n
}
