#!/bin/sh
# Merge one green PR without a re-run when main changed only outside the PR's
# classes. When main changed inside them, update the branch so CI runs again
# and stop; a later call merges it.
#
# Usage: sh scripts/ci/merge-queue.sh PR_NUMBER [BASE_BRANCH]
# Needs: git, gh (signed in). Turn off "require branches to be up to date"
# in branch protection; this script is the queue.
set -e
pr=$1
base=${2:-main}
[ -n "$pr" ] || { echo "Usage: sh scripts/ci/merge-queue.sh PR_NUMBER [BASE_BRANCH]" >&2; exit 2; }

here=$(dirname "$0")
. "$here/lib.sh"
rules=$(cat "$here/classes.txt")

git fetch -q origin "$base" "pull/$pr/head"
head=$(gh pr view "$pr" --json headRefOid -q .headRefOid)
merge_base=$(git merge-base "origin/$base" "$head")

pr_classes=$(classify_paths "$(git diff --name-only "$merge_base" "$head")" "$rules")
main_classes=$(classify_paths "$(git diff --name-only "$merge_base" "origin/$base")" "$rules")

if ! gh pr checks "$pr" >/dev/null 2>&1; then
  echo "PR $pr is not green yet; nothing merged."
  exit 0
fi

if [ "$(needs_rerun "$pr_classes" "$main_classes")" = yes ]; then
  echo "main moved in a class PR $pr touches (PR: ${pr_classes:-none}; main: ${main_classes:-none}); updating the branch so CI runs again."
  gh pr update-branch "$pr"
  exit 0
fi

echo "main moved only outside PR $pr's classes (PR: ${pr_classes:-none}; main: ${main_classes:-none}); merging without a re-run."
gh pr merge "$pr" --squash
