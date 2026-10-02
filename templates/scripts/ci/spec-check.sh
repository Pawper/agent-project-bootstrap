#!/bin/sh
# Fail when a change touches src/ without a change in its feature's spec
# folder. Warn when it touches more than one spec folder.
# Usage: git diff --name-only BASE HEAD | sh scripts/ci/spec-check.sh
#    or: sh scripts/ci/spec-check.sh BASE HEAD
here=$(dirname "$0")
. "$here/lib.sh"

if [ $# -ge 2 ]; then
  paths=$(git diff --name-only "$1" "$2")
else
  paths=$(cat)
fi

case "$(spec_check_reason "$paths")" in
  missing)
    echo "This change touches src/ but no spec folder under specs/; add or update specs/<feature>/spec.md in the same PR (the constitution does not count)." >&2
    exit 1
    ;;
  many*)
    echo "This change touches more than one spec folder; that usually means the task was too big for one PR. Not failing, but consider splitting it."
    ;;
  *)
    echo "Spec check passed."
    ;;
esac
