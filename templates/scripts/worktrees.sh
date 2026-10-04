#!/bin/sh
# The sanctioned way to tidy worktrees. A worktree is a checkout, not the
# work: its commits live in the branch, which this script never removes.
# So removing the worktree of a merged branch loses nothing, and it is the
# one cleanup the no-delete rule allows, through this script only.
#
# Usage, from the main checkout:
#   sh scripts/worktrees.sh list             how many, in which folders, how many are prunable
#   sh scripts/worktrees.sh prune            print what would be removed; remove nothing
#   sh scripts/worktrees.sh prune --apply    remove the worktrees of merged branches that are clean
#   sh scripts/worktrees.sh prune --apply --branch NAME   only that branch (the merge queue uses this)
#
# A branch counts as merged when git says it is merged into the default
# branch, or when its pull request was merged on GitHub (one call, so squash
# merges count too). A worktree with uncommitted changes is never removed;
# it is listed as skipped. Branches are kept either way.
set -e
here=$(dirname "$0")
. "$here/worktrees-lib.sh"

cmd=${1:-list}
apply=no; only=""
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=yes ;;
    --branch) shift; only=$1 ;;
  esac
  shift
done

default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo main)
pairs=$(worktree_branches "$(git worktree list --porcelain)")
count=$(printf '%s\n' "$pairs" | sed '/^$/d' | wc -l | tr -d ' ')

merged=$(git branch --merged "$default" --format='%(refname:short)' 2>/dev/null)
if command -v gh >/dev/null 2>&1; then
  merged="$merged
$(gh pr list --state merged --limit 300 --json headRefName --jq '.[].headRefName' 2>/dev/null || true)"
fi
prunable=$(prunable_worktrees "$pairs" "$merged" "$only")
pcount=$(printf '%s\n' "$prunable" | sed '/^$/d' | wc -l | tr -d ' ')

case "$cmd" in
  list)
    echo "$count worktrees besides the main checkout; $pcount belong to merged branches."
    worktree_places "$pairs" | awk -F'\t' '{ printf "  %s in %s\n", $1, $2 }'
    [ "$pcount" -gt 0 ] && echo "Run: sh scripts/worktrees.sh prune   to see them, then add --apply."
    ;;
  prune)
    if [ "$pcount" -eq 0 ]; then echo "Nothing to prune."; exit 0; fi
    removed=0; skipped=0
    printf '%s\n' "$prunable" | while IFS= read -r path; do
      [ -n "$path" ] || continue
      if [ -n "$(git -C "$path" status --porcelain 2>/dev/null | head -n 1)" ]; then
        echo "skipped $path: it has uncommitted changes"
        continue
      fi
      if [ "$apply" = yes ]; then
        git worktree remove "$path" >/dev/null 2>&1 && echo "removed $path" || echo "skipped $path: git would not remove it"
      else
        echo "would remove $path"
      fi
    done
    if [ "$apply" = yes ]; then
      git worktree prune
      echo "Done. Branches were kept."
    else
      echo "$pcount worktrees belong to merged branches. Nothing was removed; add --apply to remove the clean ones."
    fi
    ;;
  *)
    echo "Usage: sh scripts/worktrees.sh list | prune [--apply] [--branch NAME]" >&2
    exit 2
    ;;
esac
