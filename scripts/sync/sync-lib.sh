#!/bin/sh
# Pure helpers for the template refresh. Text in, text out.

# owned_paths OWNED
# OWNED is the text of templates/OWNED.txt. Print the plugin-owned paths,
# one per line.
owned_paths() {
  printf '%s\n' "$1" | tr -d '\r' | awk 'NF && $1 !~ /^#/ && $1 != "default" { print $1 }'
}

# default_paths OWNED
# The config files with defaults: added when missing, never replaced.
default_paths() {
  printf '%s\n' "$1" | tr -d '\r' | awk '$1 == "default" && NF >= 2 { print $2 }'
}

# same_text A B
# "yes" when two texts are equal ignoring carriage returns and a trailing
# newline, "no" otherwise. A Windows checkout is not a change.
same_text() {
  st_a=$(printf '%s' "$1" | tr -d '\r')
  st_b=$(printf '%s' "$2" | tr -d '\r')
  if [ "$st_a" = "$st_b" ]; then echo yes; else echo no; fi
}

# workflow_jobs YAML
# The job names a workflow defines: keys indented two spaces under "jobs:".
workflow_jobs() {
  printf '%s\n' "$1" | tr -d '\r' | awk '
    /^jobs:[ \t]*$/ { in_jobs = 1; next }
    /^[^ \t#]/ { in_jobs = 0 }
    in_jobs && /^  [A-Za-z0-9_-]+:[ \t]*$/ { k = $1; sub(/:$/, "", k); print k }'
}

# missing_jobs TEMPLATE_YAML PROJECT_YAML
# Jobs the template workflow has that the project's copy does not. The
# project owns its ci.yml, so these are reported, not added.
missing_jobs() {
  mj_have=$(workflow_jobs "$2")
  workflow_jobs "$1" | while IFS= read -r mj_j; do
    printf '%s\n' "$mj_have" | grep -qxF "$mj_j" || printf '%s\n' "$mj_j"
  done
}

# missing_lines TEMPLATE PROJECT
# Lines of a template file (not comments, not blank) that the project's
# copy lacks, such as an attribute in .gitattributes or a path in
# .gitignore. Reported, not added.
missing_lines() {
  ml_have=$(printf '%s\n' "$2" | tr -d '\r')
  printf '%s\n' "$1" | tr -d '\r' | awk 'NF && $0 !~ /^[ \t]*#/' | while IFS= read -r ml_l; do
    printf '%s\n' "$ml_have" | grep -qxF "$ml_l" || printf '%s\n' "$ml_l"
  done
}
