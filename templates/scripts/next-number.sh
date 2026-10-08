#!/bin/sh
# Reserve the next free number for a numbered file, across main and every
# open pull request, so two agents never take the same one.
#
# Usage: sh scripts/next-number.sh migration
#
# The kinds and where their files live are in .claude/numbering.txt, one
# per line: "KIND GLOB", for example
#   migration supabase/migrations/*.sql
# It reads the files on the default branch (local git, after a fetch) and
# the files every open pull request adds (one gh call), and prints the next
# number after the largest, padded the same way.
#
# For anything that does not have to run in order, use the issue number
# instead: a setup step "for #123", a task "#123". Issue numbers never
# collide, and nothing has to be reserved.
set -e
here=$(dirname "$0")
. "$here/ci/numbering-lib.sh"

kind=$1
[ -n "$kind" ] || { echo "Usage: sh scripts/next-number.sh KIND   (kinds are listed in .claude/numbering.txt)" >&2; exit 2; }
[ -f .claude/numbering.txt ] || { echo "There is no .claude/numbering.txt yet; add a line such as: migration supabase/migrations/*.sql" >&2; exit 2; }
glob=$(numbering_glob "$(cat .claude/numbering.txt)" "$kind")
[ -n "$glob" ] || { echo "No kind \"$kind\" in .claude/numbering.txt." >&2; exit 2; }

default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
git fetch -q origin 2>/dev/null || true
on_main=$(git ls-tree -r --name-only "$default" 2>/dev/null || true)
in_prs=""
command -v gh >/dev/null 2>&1 && in_prs=$(gh pr list --state open --limit 100 --json files --jq '.[].files[].path' 2>/dev/null || true)
here_now=$(git ls-files --others --cached 2>/dev/null || true)

all=$(printf '%s\n%s\n%s\n' "$on_main" "$in_prs" "$here_now")
next=$(next_free_number "$(numbers_in "$all" "$glob")")
echo "$next"
