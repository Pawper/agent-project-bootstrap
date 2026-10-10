#!/bin/sh
# The merge queue. Two modes:
#
#   --batch PR...   the default for more than two PRs. Make an integration
#                   branch from main, merge each PR in the order given with
#                   a merge commit, run the type-check and only the test
#                   files that PR touched after each merge, drop a PR that
#                   conflicts or goes red, rebuild the status page, push,
#                   open one PR that closes every carried issue, wait for
#                   the one full CI run, merge it, then run the serial
#                   queue for anything dropped.
#
#   --serial PR...  one at a time, as before. Merge a green PR without a
#                   re-run when main moved only outside its classes; update
#                   the branch so CI runs again when it moved inside them.
#
# Usage: sh scripts/ci/merge-queue.sh [--batch | --serial] [--base BRANCH] PR...
#        sh scripts/ci/merge-queue.sh PR [BASE]            (one PR, serial, as before)
#
# Two or fewer PRs with no flag run serially. More than two with no flag is
# refused by the require-batch-merge hook; name the mode.
#
# Needs git, gh (signed in), and for batch mode a project with a
# type-check and a test runner. Override the commands with
# QUEUE_TYPECHECK_COMMAND and QUEUE_TEST_COMMAND (the latter takes one
# file as its argument). Turn off "require branches to be up to date" in
# branch protection; this script is the queue. See scripts/ci/QUEUE.md.
set -e
here=$(dirname "$0")
. "$here/lib.sh"
. "$here/batch-lib.sh"
rules=$(cat "$here/classes.txt")

mode=""
base="main"
prs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --batch) mode=batch ;;
    --serial) mode=serial ;;
    --drain) mode=drain ;;
    --rounds) shift; rounds=$1 ;;
    --base) shift; base=$1 ;;
    --help|-h) sed -n '2,25p' "$0"; exit 0 ;;
    *[!0-9]*) [ -z "$prs" ] || base=$1 ;;
    *) prs="$prs $1" ;;
  esac
  shift
done
prs=$(batch_order $prs)
[ -n "$prs" ] || [ "$mode" = drain ] || { echo "Usage: sh scripts/ci/merge-queue.sh [--batch | --serial | --drain] [--base BRANCH] PR..." >&2; exit 2; }
count=$(printf '%s\n' "$prs" | wc -l | tr -d ' ')
if [ -z "$mode" ]; then
  if [ "$count" -gt 2 ]; then
    echo "More than two PRs need a mode: --batch (the default choice) or --serial (one at a time, by choice)." >&2
    exit 2
  fi
  mode=serial
fi

# The type-check runs once per package a change touches: the nearest
# folder above each changed file with a tsconfig.json, so a project whose
# app lives in web/ is checked from web/. QUEUE_TYPECHECK_COMMAND, when
# set, runs once from the root as the project's own command.
typecheck=${QUEUE_TYPECHECK_COMMAND:-}
ts_roots=$(git ls-files -- tsconfig.json '*/tsconfig.json' 2>/dev/null | sed 's#/tsconfig\.json$##; s#^tsconfig\.json$#.#')
if [ -z "$typecheck" ] && [ -n "$ts_roots" ]; then typecheck="npx tsc --noEmit"; fi
test_one=${QUEUE_TEST_COMMAND:-"node $here/run-test-file.mjs"}

[ -f "$here/../worktrees-lib.sh" ] && . "$here/../worktrees-lib.sh"
. "$here/run-lib.sh"
tab=$(printf '\t')

# Reading a run. One call for the run, one for its jobs, one for the
# annotations of a job that is stuck, one for our runners. Bounded waits.
wait_minutes=${QUEUE_WAIT_MINUTES:-60}
flaky_dir=.scratch/queue
mkdir -p "$flaky_dir" 2>/dev/null || true

# Staying inside GitHub's API budget (5,000 calls an hour, shared by every
# tool and agent on the account). Ten pull requests, several waits at once
# and a fast watch loop spent it in an evening; after that every wait
# failed with a 403 that read as "not green yet". So: waits poll every
# thirty seconds and never faster; before a round or a wait the queue reads
# the budget (that call is free) and sleeps until the reset when fewer
# than QUEUE_RATE_FLOOR calls are left; a 403 is named as the rate limit
# and stops the queue; and only one queue runs at a time.
gh_err=$flaky_dir/gh.err
hhmm() { date -u -d "@$1" +%H:%M 2>/dev/null || date -u -r "$1" +%H:%M 2>/dev/null || echo "$1"; }
rate_budget() { gh api rate_limit --jq '.resources.core | "\(.remaining)\t\(.reset)"' 2>/dev/null || true; }
rate_guard() {
  rg=$(rate_budget)
  w=$(rate_wait "$rg" "$(date +%s)" "${QUEUE_RATE_FLOOR:-500}")
  [ "$w" -gt 0 ] || return 0
  echo "GitHub API budget is low (${rg%%	*} calls left); waiting $((w / 60 + 1)) minute(s) until it resets at $(hhmm "${rg#*	}") UTC."
  sleep "$w"
}
# rate_stop: after a gh call whose stderr went to $gh_err, stop plainly
# when GitHub refused it for the rate limit.
rate_stop() {
  [ "$(rate_limit_hit "$(cat "$gh_err" 2>/dev/null)")" = yes ] || return 0
  rg=$(rate_budget)
  echo "GitHub API rate limit reached; it resets at $(hhmm "${rg#*	}") UTC. Stopping; run the queue again after that, and never watch a run in a loop of your own."
  exit 1
}

# One queue at a time. A queue takes .scratch/queue/lock and a second one
# is refused with a line naming the first, so agents do not start parallel
# waits that spend the same budget twice. The batch or serial run a drain
# starts itself is inside the drain's lock. A lock whose process is gone,
# or older than three hours, is a crash's leftover and is taken over.
lock_file=$flaky_dir/lock
have_lock=no
unlock() { [ "$have_lock" = yes ] && rm -f "$lock_file" 2>/dev/null; have_lock=no; }
take_lock() {
  [ -z "$QUEUE_LOCKED" ] || return 0
  l=$(cat "$lock_file" 2>/dev/null || true)
  lpid=${l%%	*}
  alive=no; [ -n "$lpid" ] && kill -0 "$lpid" 2>/dev/null && alive=yes
  why=$(queue_lock_reason "$l" "$(date +%s)" "$alive")
  if [ -n "$why" ]; then
    echo "Another queue is running: $why. Wait for it to finish rather than starting a second one."
    exit 1
  fi
  printf '%s\t%s\t%s\n' "$$" "$(date +%s)" "--$mode" > "$lock_file"
  have_lock=yes
  QUEUE_LOCKED=1; export QUEUE_LOCKED
  trap unlock EXIT
}

iso_epoch() { # ISO 8601 -> epoch seconds, GNU or BSD date
  [ -n "$1" ] || { echo 0; return; }
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || echo 0
}

latest_run() { # BRANCH -> "id<TAB>status<TAB>conclusion"
  gh run list --branch "$1" --limit 1 --json databaseId,status,conclusion --jq '.[0] | "\(.databaseId)\t\(.status)\t\(.conclusion // "")"' 2>"$gh_err" || true
}

jobs_of() { # RUN_ID -> one job per line for run_verdict
  gh run view "$1" --json jobs --jq '.jobs[] | [.name, .status, (.conclusion // ""), (.startedAt // ""), .databaseId] | @tsv' 2>/dev/null \
  | while IFS="$tab" read -r name status conc started jobid; do
    ann=""
    if [ "$status" != "completed" ]; then
      ann=$(gh api "repos/{owner}/{repo}/check-runs/$jobid/annotations" --jq '[.[].message] | join("; ")' 2>/dev/null | tr '\t\n' '  ')
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$status" "$conc" "$(iso_epoch "$started")" "$ann"
  done
}

idle_runners() { gh api 'repos/{owner}/{repo}/actions/runners' --jq '[.runners[] | select(.status == "online" and .busy == false)] | length' 2>/dev/null || echo 0; }

github_status() { # one line when GitHub says Actions is degraded, else nothing
  githubstatus_verdict "$(curl -s --max-time 5 https://www.githubstatus.com/api/v2/components.json 2>/dev/null)"
}

# diagnose RUN_ID -> prints one plain line about the run and returns:
# 0 green, 1 failed, 2 pending, 3 outage, 4 canceled
diagnose() {
  d_jobs=$(jobs_of "$1")
  d_verdict=$(run_verdict "$d_jobs" "$(date +%s)" "$(idle_runners)")
  case "$d_verdict" in
    green) return 0 ;;
    pending) return 2 ;;
    outage:*)
      gs=$(github_status)
      echo "GitHub Actions is down, not your code: ${d_verdict#outage: }${gs:+ ($gs)}"
      return 3 ;;
    canceled:*)
      echo "The run you are waiting on was canceled (${d_verdict#canceled: }); re-running it."
      return 4 ;;
    failed:*)
      echo "CI failed: ${d_verdict#failed: }"
      return 1 ;;
  esac
}

# record_flaky PR RUN_ID RESULT: keep the per-test record. On a failure,
# the failing tests are read from the run's log; on a pass, the tests that
# failed earlier on this PR are marked passed, which is what a flake is.
record_flaky() {
  rf_log=""; [ -f "$flaky_dir/flaky.tsv" ] && rf_log=$(cat "$flaky_dir/flaky.tsv")
  rf_day=$(date +%Y-%m-%d)
  if [ "$3" = failed ]; then
    tests=$(failed_tests_from_log "$(gh run view "$2" --log-failed 2>/dev/null)")
    # A class job that failed with no test named (a lost log, a runner
    # hiccup) is recorded by its job name, so a job that fails and then
    # passes on re-run is the same flake signal as a test.
    [ -n "$tests" ] || tests=$(jobs_of "$2" | awk -F'\t' '$3 == "failure" { print "job:" $1 }')
    [ -n "$tests" ] && echo "Failing tests: $(printf '%s\n' "$tests" | head -n 5 | tr '\n' ';' | sed 's/;$//')"
  else
    tests=$(printf '%s\n' "$rf_log" | awk -F'\t' -v pr="$1" '$2 == pr && $4 == "failed" { print $3 }' | awk '!seen[$0]++')
  fi
  for t in $(printf '%s\n' "$tests" | tr ' ' '\001'); do
    t=$(printf '%s' "$t" | tr '\001' ' ')
    rf_log=$(flaky_log_add "$rf_log" "$rf_day" "$1" "$t" "$3")
  done
  printf '%s\n' "$rf_log" > "$flaky_dir/flaky.tsv"
  # A test that flaked twice gets an issue, once.
  flaky_offenders "$rf_log" 2 | while IFS="$tab" read -r count test prs; do
    [ -n "$test" ] || continue
    grep -qxF "$test" "$flaky_dir/flaky-filed.txt" 2>/dev/null && continue
    gh issue create --title "Flaky test: $test" --label "bug,state:ready" \
      --body "This test failed and then passed on retry $count times, on pull requests $prs. The merge queue recorded it. An unreliable test is a bug, not weather: fix it or quarantine it with its own issue, do not re-run it again." >/dev/null 2>&1 \
      && { printf '%s\n' "$test" >> "$flaky_dir/flaky-filed.txt"; echo "Filed an issue for the flaky test $test ($count flakes on $prs)."; }
  done
}

# wait_for_run PR BRANCH: wait for the branch's latest run, saying plainly
# what is happening. Returns 0 green, 1 red, 3 gave up.
wait_for_run() {
  w_start=$(date +%s); outage_on=no
  while :; do
    rate_guard
    run=$(latest_run "$2"); run_id=${run%%	*}
    rate_stop
    [ -n "$run_id" ] || { echo "No run found for $2 yet."; sleep 30; continue; }
    msg=$(diagnose "$run_id"); code=$?
    [ -n "$msg" ] && echo "$msg"
    case $code in
      0) record_flaky "$1" "$run_id" passed
         if [ "$outage_on" = yes ] && [ -n "$QUEUE_OUTAGE_OFF" ]; then sh -c "$QUEUE_OUTAGE_OFF" && echo "Outage switch off again."; fi
         return 0 ;;
      1) record_flaky "$1" "$run_id" failed; return 1 ;;
      3) if [ "$outage_on" = no ] && [ -n "$QUEUE_OUTAGE_ON" ]; then sh -c "$QUEUE_OUTAGE_ON" && { outage_on=yes; echo "Outage switch on for this run."; }; fi ;;
      4) gh run rerun "$run_id" >/dev/null 2>&1 || true ;;
    esac
    if [ $(( $(date +%s) - w_start )) -gt $((wait_minutes * 60)) ]; then
      echo "Waited $wait_minutes minutes for run $run_id; giving up for now. Run the queue again later."
      return 3
    fi
    sleep 30
  done
}

# wait_quiet_main: do not merge while a run on main is in flight, so a
# proof run on main is never canceled by the queue, and a manual run on
# main can expect a quiet main.
wait_quiet_main() {
  q_start=$(date +%s)
  while :; do
    runs=$(gh run list --branch "$base" --limit 10 --json databaseId,headBranch,status,event --jq '.[] | [.databaseId, .headBranch, .status, .event] | @tsv' 2>/dev/null | sed "s/\t$base\t/\tmain\t/")
    [ "$(main_in_flight "$runs")" = yes ] || return 0
    [ $(( $(date +%s) - q_start )) -lt 1200 ] || { echo "A run on $base has been in flight for twenty minutes; merging anyway."; return 0; }
    echo "Holding the merge: a run on $base is in flight."
    sleep 30
  done
}

# worktree_of BRANCH: the local worktree that has the branch checked out.
worktree_of() {
  command -v worktree_for_branch >/dev/null 2>&1 || return 0
  worktree_for_branch "$(worktree_branches "$(git worktree list --porcelain)")" "$1"
}

# folder_blocks PR: print why a PR may not be queued when its worktree has
# uncommitted files outside .scratch/. The folder is checked when the PR is
# queued, not after the merge, so a file written minutes before is caught.
folder_blocks() {
  fb_branch=$(gh pr view "$1" --json headRefName -q .headRefName 2>/dev/null || true)
  fb_path=$(worktree_of "$fb_branch")
  [ -n "$fb_path" ] || return 0
  fb_dirty=$(dirty_non_scratch "$(git -C "$fb_path" status --porcelain 2>/dev/null)")
  [ -n "$fb_dirty" ] || return 0
  printf 'its worktree has %s uncommitted file(s) outside .scratch/, first: %s\n' \
    "$(printf '%s\n' "$fb_dirty" | wc -l | tr -d ' ')" "$(printf '%s\n' "$fb_dirty" | head -n 1)"
}

# migration_blocks PR: print why a PR may not merge yet when it adds a
# migration that its own copy of the manual does not mark as done. A change
# that needs a migration run merges after the run, not before. The manual
# is SETUP.md or the "manual" line in setup-paths.txt; migrations are the
# "migration" kind in .claude/numbering.txt.
. "$here/numbering-lib.sh"
migration_blocks() {
  [ -f .claude/numbering.txt ] || return 0
  mb_glob=$(numbering_glob "$(cat .claude/numbering.txt)" migration)
  [ -n "$mb_glob" ] || return 0
  mb_manual=SETUP.md
  [ -f "$here/setup-paths.txt" ] && mb_manual=$(setup_manual "$(cat "$here/setup-paths.txt")")
  git fetch -q origin "$base" "pull/$1/head" 2>/dev/null || return 0
  mb_head=$(git rev-parse FETCH_HEAD)
  mb_added=$(git diff --name-only --diff-filter=A "origin/$base...$mb_head" 2>/dev/null)
  mb_pending=$(pending_migrations "$(git show "$mb_head:$mb_manual" 2>/dev/null)" "$mb_added" "$mb_glob")
  [ -n "$mb_pending" ] || return 0
  printf '%s\n' "$mb_pending" | head -n 1 | awk -F'\t' -v m="$mb_manual" '{ printf "it adds migration %s, which is %s in %s; run it, mark it Done in the manual on this branch, then queue it again\n", $1, $2, m }'
}

# sync_worktree BRANCH: never move a branch from outside its worktree. When
# the queue advances a branch on the remote, bring the worktree's files
# along, so the folder does not look full of edits it never made.
sync_worktree() {
  sw_path=$(worktree_of "$1")
  [ -n "$sw_path" ] || return 0
  git -C "$sw_path" pull -q --ff-only >/dev/null 2>&1 || echo "note: the worktree at $sw_path could not fast-forward; update it by hand before working there"
}

# serial_one PR: today's behavior for one PR.
serial_one() {
  pr=$1
  why=$(folder_blocks "$pr"); [ -n "$why" ] || why=$(migration_blocks "$pr")
  if [ -n "$why" ]; then batch_line "$pr" "refused" "$why"; return 0; fi
  git fetch -q origin "$base" "pull/$pr/head"
  head=$(gh pr view "$pr" --json headRefOid -q .headRefOid)
  merge_base=$(git merge-base "origin/$base" "$head")
  pr_classes=$(classify_paths "$(git diff --name-only "$merge_base" "$head")" "$rules")
  main_classes=$(classify_paths "$(git diff --name-only "$merge_base" "origin/$base")" "$rules")
  if ! gh pr checks "$pr" >/dev/null 2>"$gh_err"; then
    rate_stop
    hb=$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null || true)
    run=$(latest_run "$hb"); run_id=${run%%	*}
    rate_stop
    why="not green yet, nothing merged"
    if [ -n "$run_id" ]; then
      msg=$(diagnose "$run_id"); code=$?
      case $code in
        1) record_flaky "$pr" "$run_id" failed; why="$msg" ;;
        3) why="$msg" ;;
        4) gh run rerun "$run_id" >/dev/null 2>&1 || true; why="$msg" ;;
      esac
    fi
    batch_line "$pr" "waiting" "$why"
    return 0
  fi
  if [ "$(needs_rerun "$pr_classes" "$main_classes" "$(rerun_free_classes "$rules")")" = yes ]; then
    gh pr update-branch "$pr" >/dev/null
    sync_worktree "$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null || true)"
    batch_line "$pr" "updated" "main moved in its classes (PR: ${pr_classes:-none}; main: ${main_classes:-none}), CI runs again"
    return 0
  fi
  head_branch=$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null || true)
  record_flaky "$pr" "" passed
  wait_quiet_main
  gh pr merge "$pr" --squash >/dev/null
  batch_line "$pr" "merged serially" "main moved only outside its classes"
  tidy_worktree "$head_branch"
}

# typecheck_ok PATHS [DIR]: the type-check, run once in each package the
# change touches (the nearest folder above each changed file with a
# tsconfig.json), or once from the root when QUEUE_TYPECHECK_COMMAND names
# the project's own command. DIR is the checkout to run in (default here).
# Returns non-zero on the first red package, with its output in
# .scratch/queue/typecheck.err so the caller can name the first error.
typecheck_ok() {
  tc_root=${2:-.}
  : > "$flaky_dir/typecheck.err"
  if [ -n "$QUEUE_TYPECHECK_COMMAND" ] || [ -z "$ts_roots" ]; then (cd "$tc_root" && sh -c "$typecheck") >"$flaky_dir/typecheck.err" 2>&1; return $?; fi
  tc_dirs=$(printf '%s\n' "$1" | while IFS= read -r tc_f; do [ -n "$tc_f" ] && nearest_root "$tc_f" "$ts_roots"; done | sort -u)
  for tc_d in $tc_dirs; do
    [ -f "$tc_root/$tc_d/tsconfig.json" ] || continue
    (cd "$tc_root/$tc_d" && sh -c "$typecheck") >"$flaky_dir/typecheck.err" 2>&1 || return 1
  done
  return 0
}

# tidy_worktree BRANCH: remove the worktree of a branch that just merged,
# when it is clean. The branch itself is kept. Quiet when there is none.
tidy_worktree() {
  [ -n "$1" ] && [ -f "$here/../worktrees.sh" ] || return 0
  sh "$here/../worktrees.sh" prune --apply --branch "$1" 2>/dev/null | grep '^removed' || true
}

# Drain: merge everything that is green, round after round, so nobody
# writes their own loop. Each round reads every open pull request in one
# call, merges the green ones (as a batch when more than two), and waits
# for the running ones. It stops when nothing is green and nothing is
# running, when nothing new turned green, after --rounds rounds (default
# six), or after QUEUE_DRAIN_MINUTES (default ninety).
take_lock
if [ "$mode" = drain ]; then
  rounds=${rounds:-6}
  drain_minutes=${QUEUE_DRAIN_MINUTES:-90}
  d_start=$(date +%s); round=0; tried=""; retried=""; attention=""
  while [ "$round" -lt "$rounds" ]; do
    round=$((round + 1))
    rate_guard
    open=$(gh pr list --state open --limit 100 --json number,isDraft,mergeable,statusCheckRollup,baseRefName --jq '
      .[] | [ .number, .isDraft, .mergeable,
        ( [ .statusCheckRollup[]? | (.conclusion // .state // "") ] as $s
          | if ($s | length) == 0 then "none"
            elif any($s[]; test("FAILURE|ERROR|TIMED_OUT|CANCELLED|ACTION_REQUIRED")) then "red"
            elif any($s[]; . == "" or test("PENDING|EXPECTED|QUEUED|IN_PROGRESS")) then "pending"
            else "green" end ),
        .baseRefName ] | @tsv' 2>"$gh_err" || true)
    rate_stop
    # A red pull request gets one retry of its failed jobs; a second red,
    # or a conflict, is collected and named when the drain ends.
    for r in $(drain_retry "$open" "$base" "$retried"); do
      rb=$(gh pr view "$r" --json headRefName -q .headRefName 2>/dev/null || true)
      rid=$(latest_run "$rb"); rid=${rid%%	*}
      if [ -n "$rid" ] && gh run rerun "$rid" --failed >/dev/null 2>&1; then
        echo "round $round: #$r failed CI; re-running its failed jobs once."
      fi
      retried="$retried $r"
    done
    attention=$(printf '%s
%s
' "$attention" "$(drain_attention "$open" "$base" "$retried")" | sed '/^$/d' | sort -u -n)
    pick=$(drain_candidates "$open" "$base" "$tried")
    waiting=$(drain_waiting "$open" "$base")
    n=$(printf '%s\n' "$pick" | sed '/^$/d' | wc -l | tr -d ' ')
    elapsed=$(( $(date +%s) - d_start ))
    if [ "$n" -gt 0 ] && [ "$(drain_hold "$n" "$waiting")" = yes ] && [ "$elapsed" -lt $((drain_minutes * 60)) ]; then
      # A serial merge now would move main under the ones still running
      # and send them back round CI; the batch after it would be empty.
      echo "round $round: $n green, $waiting still running CI; holding the serial merge until they finish, so it does not send them back round CI."
      round=$((round - 1))
      sleep 120
      continue
    fi
    if [ "$n" -eq 0 ]; then
      if [ "$waiting" -gt 0 ] && [ "$elapsed" -lt $((drain_minutes * 60)) ]; then
        echo "round $round: nothing new is green; $waiting pull request(s) still running CI, waiting two minutes."
        sleep 120
        continue
      fi
      if [ "$waiting" -gt 0 ]; then echo "round $round: nothing new is green, and $waiting still running after $drain_minutes minutes; stopping."
      else echo "round $round: nothing left to merge."; fi
      break
    fi
    echo "round $round: $n green pull request(s): $(printf '%s' "$pick" | tr '\n' ' ')"
    QUEUE_IN_DRAIN=1; export QUEUE_IN_DRAIN
    if [ "$n" -gt 2 ]; then sh "$0" --batch --base "$base" $pick || true; else sh "$0" --serial --base "$base" $pick || true; fi
    tried="$tried $(printf '%s' "$pick" | tr '\n' ' ')"
    if [ $(( $(date +%s) - d_start )) -ge $((drain_minutes * 60)) ]; then
      echo "Drained for $drain_minutes minutes; stopping. Run --drain again to go on."
      break
    fi
  done
  echo "queue done"
  if [ -n "$attention" ]; then
    echo "Needs attention:"
    printf '%s\n' "$attention" | awk -F'\t' '{ printf "  #%s %s\n", $1, $2 }'
    exit 1
  fi
  exit 0
fi

if [ "$mode" = serial ]; then
  for pr in $prs; do serial_one "$pr"; done
  [ -n "$QUEUE_IN_DRAIN" ] || echo "queue done"
  exit 0
fi

# Batch mode. The batch is built in its own worktree, never in the main
# checkout, so a person working there is not switched onto the batch
# branch under their feet. QUEUE_WORKTREE names the folder; the default is
# a sibling of the repository called <repo>-wt-batch, which is reused from
# one batch to the next. Each package's node_modules is linked from the
# main checkout when the worktree has none, so nothing is installed twice.
git fetch -q origin "$base"
day=$(date +%Y-%m-%d)  # the owner's local day, like every date in the repository
n=1
branch=$(batch_branch_name "$day" "$n")
while git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; do
  n=$((n + 1)); branch=$(batch_branch_name "$day" "$n")
done
main_dir=$(pwd)
wt=${QUEUE_WORKTREE:-"$(cd .. && pwd)/$(basename "$main_dir")-wt-batch"}
if [ -e "$wt/.git" ]; then
  git -C "$wt" checkout -q -B "$branch" "origin/$base"
else
  git worktree add -q -B "$branch" "$wt" "origin/$base"
fi
# link_modules: a junction on Windows, a symlink elsewhere, for each
# package's node_modules the worktree lacks and the main checkout has.
link_modules() {
  git ls-files -- package.json '*/package.json' 2>/dev/null | sed 's#/package\.json$##; s#^package\.json$#.#' | while IFS= read -r d; do
    [ -d "$main_dir/$d/node_modules" ] && [ ! -e "$wt/$d/node_modules" ] || continue
    mkdir -p "$wt/$d"
    case "$(uname -s 2>/dev/null)" in
      MINGW*|MSYS*|CYGWIN*) cmd //c mklink /J "$(cygpath -w "$wt/$d/node_modules")" "$(cygpath -w "$main_dir/$d/node_modules")" >/dev/null 2>&1 || true ;;
      *) ln -s "$main_dir/$d/node_modules" "$wt/$d/node_modules" 2>/dev/null || true ;;
    esac
  done
}
link_modules
echo "batch branch $branch in $wt from origin/$base"

# The base is checked before anything is merged. A red base (packages not
# installed, generated types stale) made every pull request look red
# after its merge, and all of them were dropped for a fault none of them
# had. Nothing is dropped for that; the batch stops and says what is red.
if [ -n "$typecheck" ] && ! typecheck_ok "$(git -C "$wt" ls-files)" "$wt"; then
  echo "origin/$base is red here before any merge: $(head -n 1 "$flaky_dir/typecheck.err" 2>/dev/null | tr -d '\r')"
  echo "Nothing was dropped for it. Fix the checkout at $wt (install the packages, regenerate the types) and run the batch again."
  exit 1
fi

carried=""
dropped=""
good=$(git -C "$wt" rev-parse HEAD)
for pr in $prs; do
  why=$(folder_blocks "$pr"); [ -n "$why" ] || why=$(migration_blocks "$pr")
  if [ -n "$why" ]; then batch_line "$pr" "refused" "$why"; continue; fi
  git -C "$wt" fetch -q origin "pull/$pr/head" || { batch_line "$pr" "dropped" "could not fetch it"; dropped="$dropped $pr"; continue; }
  head=$(git -C "$wt" rev-parse FETCH_HEAD)
  title=$(gh pr view "$pr" --json title -q .title 2>/dev/null || echo "PR $pr")
  if ! git -C "$wt" merge -q --no-ff --no-edit -m "Merge PR #$pr into $branch: $title" "$head" >/dev/null 2>&1; then
    git -C "$wt" merge --abort >/dev/null 2>&1 || true
    git -C "$wt" reset -q --hard "$good"
    batch_line "$pr" "dropped" "conflicts with the batch so far"
    dropped="$dropped $pr"
    continue
  fi
  changed=$(git -C "$wt" diff --name-only "origin/$base...$head")
  if [ -n "$typecheck" ] && ! typecheck_ok "$changed" "$wt"; then
    git -C "$wt" reset -q --hard "$good"
    batch_line "$pr" "dropped" "the type-check went red after merging it: $(head -n 1 "$flaky_dir/typecheck.err" 2>/dev/null | tr -d '\r')"
    dropped="$dropped $pr"
    continue
  fi
  red=""
  for f in $(tests_for_diff "$changed"); do
    [ -f "$wt/$f" ] || continue
    rc=0; (cd "$wt" && $test_one "$f") >/dev/null 2>"$flaky_dir/test.err" || rc=$?
    if [ "$rc" -eq 2 ]; then
      # The runner could not start. That is not a red test, and dropping
      # every pull request for it would empty the batch for nothing.
      echo "The test runner could not run $f: $(tail -n 3 "$flaky_dir/test.err" 2>/dev/null | tr '\r\n' '  ')"
      echo "Nothing was dropped for it. Fix the runner, or set QUEUE_TEST_COMMAND to the project's one-file test command, and run the batch again."
      git -C "$wt" reset -q --hard "$good"
      exit 1
    fi
    if [ "$rc" -ne 0 ]; then
      red=$f
      [ -s "$flaky_dir/test.err" ] && echo "  $(tail -n 3 "$flaky_dir/test.err" | tr '\r\n' '  ')"
      break
    fi
  done
  if [ -n "$red" ]; then
    git -C "$wt" reset -q --hard "$good"
    batch_line "$pr" "dropped" "$red went red after merging it"
    dropped="$dropped $pr"
    continue
  fi
  # Cancel the PR's own CI run; the batch's one run covers it.
  gh run list --branch "$(gh pr view "$pr" --json headRefName -q .headRefName)" --status in_progress --json databaseId -q '.[].databaseId' 2>/dev/null \
    | while read -r id; do [ -n "$id" ] && gh run cancel "$id" >/dev/null 2>&1 || true; done
  good=$(git -C "$wt" rev-parse HEAD)
  carried="$carried$pr	$title
"
  batch_line "$pr" "merged into the batch"
done

if [ -z "$carried" ]; then
  echo "Nothing survived the batch; running the serial queue for all of them."
  for pr in $dropped; do serial_one "$pr"; done
  exit 0
fi

if [ -f "$wt/status/build.sh" ]; then
  (cd "$wt" && sh status/build.sh) >/dev/null
  if ! git -C "$wt" diff --quiet -- STATUS.md; then
    git -C "$wt" add STATUS.md && git -C "$wt" commit -q -m "Rebuild the status page for $branch"
  fi
fi

git -C "$wt" push -q -u origin "$branch"
body=$(batch_pr_body "$carried")
batch_pr=$(gh pr create --base "$base" --head "$branch" --title "Batch $day: $(printf '%s' "$carried" | wc -l | tr -d ' ') pull requests" --body "$body" --json number -q .number 2>/dev/null \
  || gh pr create --base "$base" --head "$branch" --title "Batch $day" --body "$body" | sed 's#.*/##')
echo "batch PR #$batch_pr opened; waiting for the one full CI run"
if ! wait_for_run "$batch_pr" "$branch"; then
  echo "The batch run is not green; nothing merged. Fix it on $branch or drop a PR and run again."
  exit 1
fi
wait_quiet_main
gh pr merge "$batch_pr" --merge >/dev/null
echo "batch PR #$batch_pr merged into $base with a merge commit"
for pr in $(printf '%s' "$carried" | cut -f1); do
  tidy_worktree "$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null || true)"
done
[ -n "$QUEUE_IN_DRAIN" ] || echo "queue done"

if [ -n "$dropped" ]; then
  echo "serial queue for the dropped PRs:$dropped"
  for pr in $dropped; do serial_one "$pr"; done
fi
