#!/bin/sh
# Pure helpers for CI: classify changed paths, decide whether a merge needs a
# re-run, and read the State field out of an issue body.

# classify_paths PATHS RULES
# PATHS is one path per line. RULES is the text of classes.txt. Print the
# matching classes, sorted, space separated. A path that matches no rule is
# class "other".
classify_paths() {
  cp_rules=$2
  set -f
  printf '%s\n' "$1" | tr -d '\r' | tr '\\' '/' | while IFS= read -r cp_p; do
    [ -n "$cp_p" ] || continue
    cp_cls=
    while IFS= read -r cp_line; do
      cp_line=${cp_line%%#*}
      set -- $cp_line
      [ $# -ge 2 ] || continue
      cp_c=$1
      shift
      for cp_pat in "$@"; do
        case "$cp_p" in $cp_pat) cp_cls=$cp_c; break ;; esac
      done
      [ -n "$cp_cls" ] && break
    done <<EOF
$cp_rules
EOF
    printf '%s\n' "${cp_cls:-other}"
  done | sort -u | tr '\n' ' ' | sed 's/ $//'
  set +f
}

# needs_rerun PR_CLASSES MAIN_CLASSES
# Print "yes" when a green PR must run CI again before merging because main
# moved in a class the PR touches, in the ci class, or in an unclassified
# file. Print "no" when main moved only outside the PR's classes.
needs_rerun() {
  for nr_a in $1; do
    for nr_b in $2; do
      [ "$nr_a" = "$nr_b" ] && { echo yes; return 0; }
    done
  done
  case " $1 $2 " in *" other "*) echo yes; return 0 ;; esac
  case " $2 " in *" ci "*) echo yes; return 0 ;; esac
  echo no
}

# state_label_from_body BODY
# Print the state label for the "### State" field in an issue body written
# by the task template, for example "state:waiting-on-owner". Print nothing
# when the field is missing or empty.
state_label_from_body() {
  printf '%s\n' "$1" | tr -d '\r' | awk '
    found && $0 !~ /^[ \t]*$/ {
      v = tolower($0)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (v == "_no response_") exit
      gsub(/[ \t]+/, "-", v)
      print "state:" v
      exit
    }
    /^### State[ \t]*$/ { found = 1 }
  '
}

# issues_without_state LINES
# Each line is "NUMBER label,label,...". Print the numbers whose labels
# include no "state:" label, one per line.
issues_without_state() {
  printf '%s\n' "$1" | tr -d '\r' | awk '
    NF >= 1 {
      labels = (NF >= 2) ? $2 : ""
      if ("," labels "," !~ /,state:/) print $1
    }'
}

# issue_refs TEXT
# Print every issue number TEXT refers to as #N, one per line, unique.
issue_refs() {
  printf '%s\n' "$1" | tr -d '\r' | awk '
    {
      s = $0
      while (match(s, /#[0-9]+/)) {
        n = substr(s, RSTART + 1, RLENGTH - 1)
        if (!(n in seen)) { seen[n] = 1; print n }
        s = substr(s, RSTART + RLENGTH)
      }
    }'
}

# audit_comment MISSING STALE
# MISSING is issue numbers one per line; STALE is "PR ISSUE" pairs one per
# line. Print the comment body, or nothing when both are empty.
audit_comment() {
  ac_missing=$(printf '%s\n' "$1" | sed '/^[ \t]*$/d')
  ac_stale=$(printf '%s\n' "$2" | sed '/^[ \t]*$/d')
  [ -n "$ac_missing" ] || [ -n "$ac_stale" ] || return 0
  if [ -n "$ac_missing" ]; then
    printf 'Open issues with no State label:\n'
    printf '%s\n' "$ac_missing" | awk '{ printf "- #%s\n", $1 }'
  fi
  if [ -n "$ac_stale" ]; then
    [ -n "$ac_missing" ] && printf '\n'
    printf 'Issues still open and labeled ready after their PR merged:\n'
    printf '%s\n' "$ac_stale" | awk '{ printf "- #%s (merged in #%s)\n", $2, $1 }'
  fi
}
