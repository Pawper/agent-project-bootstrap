#!/bin/sh
# Pure helpers for the worktree script. No git, no gh; text in, text out.

# worktree_branches PORCELAIN
# PORCELAIN is the output of git worktree list --porcelain. Print one line
# per worktree after the first (the main checkout): "path<TAB>branch". A
# detached worktree has an empty branch.
worktree_branches() {
  printf '%s\n' "$1" | tr -d '\r' | awk '
    /^worktree / { if (n > 1) print path "\t" branch; n++; path = substr($0, 10); branch = "" }
    /^branch / { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
    END { if (n > 1) print path "\t" branch }'
}

# prunable_worktrees PATH_BRANCH MERGED [ONLY_BRANCH]
# PATH_BRANCH is the output of worktree_branches. MERGED is one merged
# branch name per line. Print the paths of worktrees whose branch is in
# MERGED, one per line. With ONLY_BRANCH, consider that branch alone.
# A worktree with no branch is never prunable.
prunable_worktrees() {
  printf '%s\n' "$1" | awk -F'\t' -v merged="$2" -v only="$3" '
    BEGIN { n = split(merged, m, "\n"); for (i = 1; i <= n; i++) { b = m[i]; gsub(/^[ \t*+]+|[ \t\r]+$/, "", b); if (b != "") ok[b] = 1 } }
    NF >= 2 && $2 != "" && ($2 in ok) && (only == "" || $2 == only) { print $1 }'
}

# worktree_places PATH_BRANCH
# Print each folder that holds worktrees with how many it holds, most
# first: "312<TAB>C:/Users/me/Documents/GitHub".
worktree_places() {
  printf '%s\n' "$1" | tr '\\' '/' | awk -F'\t' '
    NF >= 1 && $1 != "" { p = $1; sub(/\/[^\/]*$/, "", p); c[p]++ }
    END { for (p in c) printf "%d\t%s\n", c[p], p }' | sort -rn
}
