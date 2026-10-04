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
    --base) shift; base=$1 ;;
    --help|-h) sed -n '2,25p' "$0"; exit 0 ;;
    *[!0-9]*) [ -z "$prs" ] || base=$1 ;;
    *) prs="$prs $1" ;;
  esac
  shift
done
prs=$(batch_order $prs)
[ -n "$prs" ] || { echo "Usage: sh scripts/ci/merge-queue.sh [--batch | --serial] [--base BRANCH] PR..." >&2; exit 2; }
count=$(printf '%s\n' "$prs" | wc -l | tr -d ' ')
if [ -z "$mode" ]; then
  if [ "$count" -gt 2 ]; then
    echo "More than two PRs need a mode: --batch (the default choice) or --serial (one at a time, by choice)." >&2
    exit 2
  fi
  mode=serial
fi

typecheck=${QUEUE_TYPECHECK_COMMAND:-}
if [ -z "$typecheck" ] && [ -f tsconfig.json ]; then typecheck="npx tsc --noEmit"; fi
test_one=${QUEUE_TEST_COMMAND:-"node $here/run-test-file.mjs"}

# serial_one PR: today's behavior for one PR.
serial_one() {
  pr=$1
  git fetch -q origin "$base" "pull/$pr/head"
  head=$(gh pr view "$pr" --json headRefOid -q .headRefOid)
  merge_base=$(git merge-base "origin/$base" "$head")
  pr_classes=$(classify_paths "$(git diff --name-only "$merge_base" "$head")" "$rules")
  main_classes=$(classify_paths "$(git diff --name-only "$merge_base" "origin/$base")" "$rules")
  if ! gh pr checks "$pr" >/dev/null 2>&1; then
    batch_line "$pr" "waiting" "not green yet, nothing merged"
    return 0
  fi
  if [ "$(needs_rerun "$pr_classes" "$main_classes")" = yes ]; then
    gh pr update-branch "$pr" >/dev/null
    batch_line "$pr" "updated" "main moved in its classes (PR: ${pr_classes:-none}; main: ${main_classes:-none}), CI runs again"
    return 0
  fi
  head_branch=$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null || true)
  gh pr merge "$pr" --squash >/dev/null
  batch_line "$pr" "merged serially" "main moved only outside its classes"
  tidy_worktree "$head_branch"
}

# tidy_worktree BRANCH: remove the worktree of a branch that just merged,
# when it is clean. The branch itself is kept. Quiet when there is none.
tidy_worktree() {
  [ -n "$1" ] && [ -f "$here/../worktrees.sh" ] || return 0
  sh "$here/../worktrees.sh" prune --apply --branch "$1" 2>/dev/null | grep '^removed' || true
}

if [ "$mode" = serial ]; then
  for pr in $prs; do serial_one "$pr"; done
  echo "queue done"
  exit 0
fi

# Batch mode.
git fetch -q origin "$base"
day=$(date -u +%Y-%m-%d)
n=1
branch=$(batch_branch_name "$day" "$n")
while git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; do
  n=$((n + 1)); branch=$(batch_branch_name "$day" "$n")
done
git checkout -q -B "$branch" "origin/$base"
echo "batch branch $branch from origin/$base"

carried=""
dropped=""
good=$(git rev-parse HEAD)
for pr in $prs; do
  git fetch -q origin "pull/$pr/head" || { batch_line "$pr" "dropped" "could not fetch it"; dropped="$dropped $pr"; continue; }
  head=$(git rev-parse FETCH_HEAD)
  title=$(gh pr view "$pr" --json title -q .title 2>/dev/null || echo "PR $pr")
  if ! git merge -q --no-ff --no-edit -m "Merge PR #$pr into $branch: $title" "$head" >/dev/null 2>&1; then
    git merge --abort >/dev/null 2>&1 || true
    git reset -q --hard "$good"
    batch_line "$pr" "dropped" "conflicts with the batch so far"
    dropped="$dropped $pr"
    continue
  fi
  if [ -n "$typecheck" ] && ! sh -c "$typecheck" >/dev/null 2>&1; then
    git reset -q --hard "$good"
    batch_line "$pr" "dropped" "the type-check went red after merging it"
    dropped="$dropped $pr"
    continue
  fi
  red=""
  for f in $(tests_for_diff "$(git diff --name-only "origin/$base...$head")"); do
    [ -f "$f" ] || continue
    if ! $test_one "$f" >/dev/null 2>&1; then red=$f; break; fi
  done
  if [ -n "$red" ]; then
    git reset -q --hard "$good"
    batch_line "$pr" "dropped" "$red went red after merging it"
    dropped="$dropped $pr"
    continue
  fi
  # Cancel the PR's own CI run; the batch's one run covers it.
  gh run list --branch "$(gh pr view "$pr" --json headRefName -q .headRefName)" --status in_progress --json databaseId -q '.[].databaseId' 2>/dev/null \
    | while read -r id; do [ -n "$id" ] && gh run cancel "$id" >/dev/null 2>&1 || true; done
  good=$(git rev-parse HEAD)
  carried="$carried$pr	$title
"
  batch_line "$pr" "merged into the batch"
done

if [ -z "$carried" ]; then
  echo "Nothing survived the batch; running the serial queue for all of them."
  git checkout -q -
  for pr in $dropped; do serial_one "$pr"; done
  exit 0
fi

if [ -f status/build.sh ]; then
  sh status/build.sh >/dev/null
  if ! git diff --quiet -- STATUS.md; then
    git add STATUS.md && git commit -q -m "Rebuild the status page for $branch"
  fi
fi

git push -q -u origin "$branch"
body=$(batch_pr_body "$carried")
batch_pr=$(gh pr create --base "$base" --head "$branch" --title "Batch $day: $(printf '%s' "$carried" | wc -l | tr -d ' ') pull requests" --body "$body" --json number -q .number 2>/dev/null \
  || gh pr create --base "$base" --head "$branch" --title "Batch $day" --body "$body" | sed 's#.*/##')
echo "batch PR #$batch_pr opened; waiting for the one full CI run"
gh pr checks "$batch_pr" --watch >/dev/null 2>&1 || { echo "The batch run went red; nothing merged. Fix it on $branch or drop a PR and run again."; exit 1; }
gh pr merge "$batch_pr" --merge >/dev/null
echo "batch PR #$batch_pr merged into $base with a merge commit"
for pr in $(printf '%s' "$carried" | cut -f1); do
  tidy_worktree "$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null || true)"
done
echo "queue done"

if [ -n "$dropped" ]; then
  echo "serial queue for the dropped PRs:$dropped"
  git checkout -q "$base" 2>/dev/null || true
  for pr in $dropped; do serial_one "$pr"; done
fi
