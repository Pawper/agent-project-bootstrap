#!/bin/sh
# Pure helpers for the session brief. Nothing here runs git or gh; every
# function takes text and prints text, so tests/run.sh covers each with a
# fixture. The hook (session-brief.sh) gathers the raw lines and calls these.

# json_number JSON KEY
# Print the numeric value of the first "KEY" in JSON, or nothing.
json_number() {
  printf '%s' "$1" | awk -v key="\"$2\"" '
    BEGIN { RS = "\001" }
    {
      i = index($0, key)
      if (i == 0) exit
      s = substr($0, i + length(key))
      if (!sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", s)) exit
      if (match(s, /^-?[0-9]+(\.[0-9]+)?/)) print substr(s, RSTART, RLENGTH)
    }'
}

# pr_line TSV
# TSV is one pull request as "number<TAB>title<TAB>mergeable<TAB>passed
# <TAB>failed<TAB>pending", the shape gh's own jq emits for the hook. Print
# one plain line: "#12 Title (mergeable, CI 3 passed, 1 failed)".
pr_line() {
  printf '%s\n' "$1" | awk -F'\t' '
    {
      number = $1; title = $2; mergeable = tolower($3)
      passed = $4 + 0; failed = $5 + 0; pending = $6 + 0
      if (mergeable == "mergeable") m = "mergeable"
      else if (mergeable == "conflicting") m = "has conflicts"
      else m = "mergeability unknown"
      if (passed + failed + pending == 0) ci = "no CI yet"
      else if (failed > 0) ci = "CI " failed " failed"
      else if (pending > 0) ci = "CI " pending " pending"
      else ci = "CI green"
      printf "#%s %s (%s, %s)\n", number, title, m, ci
    }'
}

# log_is_recent MTIME NOW [WINDOW]
# MTIME and NOW are epoch seconds; WINDOW defaults to two hours. Print
# "yes" when the log was written inside the window, "no" otherwise.
log_is_recent() {
  lr_window=${3:-7200}
  case "$1" in ''|*[!0-9]*) echo no; return 0 ;; esac
  case "$2" in ''|*[!0-9]*) echo no; return 0 ;; esac
  if [ $(( $2 - $1 )) -le "$lr_window" ] && [ "$1" -le "$2" ]; then echo yes; else echo no; fi
}

# newest_handoff LIST
# LIST is one file per line as "mtime<TAB>path". Print the path of the
# newest file whose name starts with "handoff-", or nothing.
newest_handoff() {
  printf '%s\n' "$1" | tr -d '\r' | awk -F'\t' '
    NF >= 2 {
      name = $2; sub(/.*[\/\\]/, "", name)
      if (name !~ /^handoff-/) next
      if ($1 + 0 >= best) { best = $1 + 0; path = $2 }
    }
    END { if (path != "") print path }'
}

# handoff_head TEXT [N]
# Print the first N (default two) lines of the body of a note: front matter
# between --- lines and blank lines are skipped.
handoff_head() {
  hh_n=${2:-2}
  printf '%s\n' "$1" | tr -d '\r' | awk -v n="$hh_n" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm { next }
    /^[ \t]*$/ { next }
    { print; if (++c >= n) exit }'
}

# trim_section TEXT LIMIT
# Print at most LIMIT lines of TEXT; when more were cut, add one line
# saying how many.
trim_section() {
  printf '%s\n' "$1" | awk -v limit="$2" '
    NF == 0 && NR == 1 { next }
    { lines[NR] = $0; total = NR }
    END {
      shown = (total < limit) ? total : limit
      for (i = 1; i <= shown; i++) print lines[i]
      if (total > limit) printf "(and %d more)\n", total - limit
    }'
}

# brief_sections SOURCE
# Which sections to print for how the session started. A clear prints the
# short form: what is on main and what is in progress. Everything else
# prints the full brief.
brief_sections() {
  case "$1" in
    clear) echo "main inprogress" ;;
    *) echo "main prs queue inprogress handoff owner proposal" ;;
  esac
}
