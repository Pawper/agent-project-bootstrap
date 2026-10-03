#!/bin/sh
# Pure helpers shared by the hook scripts. Nothing here reads a file or
# touches the network, so every function can be tested by feeding it strings.
# Needs only POSIX sh and awk, which Git Bash, macOS and Linux all have.

# json_field JSON KEY
# Print the string value of the first "KEY" in JSON with its escapes undone.
# Prints nothing when the key is missing or its value is not a string.
json_field() {
  printf '%s' "$1" | awk -v key="\"$2\"" '
    BEGIN { RS = "\001" }
    {
      i = index($0, key)
      if (i == 0) exit
      s = substr($0, i + length(key))
      if (!sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", s)) exit
      if (substr(s, 1, 1) != "\"") exit
      n = length(s)
      out = ""
      for (j = 2; j <= n; j++) {
        c = substr(s, j, 1)
        if (c == "\\") {
          j++
          d = substr(s, j, 1)
          if (d == "n") out = out "\n"
          else if (d == "t") out = out "\t"
          else if (d == "r") out = out "\r"
          else if (d == "u") { out = out "?"; j += 4 }
          else out = out d
        } else if (c == "\"") {
          break
        } else {
          out = out c
        }
      }
      printf "%s", out
    }'
}

# split_commands COMMAND
# Print one simple command per line: the input split on &&, ||, ;, |, newlines,
# subshells and backticks, with leading VAR=value assignments and wrappers such
# as sudo, env, time and exec removed. Quotes are not parsed; this errs toward
# seeing more commands, never fewer.
split_commands() {
  printf '%s\n' "$1" | awk '
    # Pass 1: drop heredoc bodies (text is data, not commands) and join
    # lines that end in a backslash, so a command written over several
    # lines is judged whole.
    function unquote(w) { gsub(/["'\'']/, "", w); return w }
    {
      line = $0
      sub(/\r$/, "", line)
      if (inhere) {
        check = line
        if (dash) sub(/^\t+/, "", check)
        if (check == word) inhere = 0
        next
      }
      if (joining) { buf = buf " " line; gsub(/[ \t]+/, " ", buf) } else { buf = line }
      joining = 0
      if (buf ~ /\\$/) { sub(/\\$/, "", buf); joining = 1; next }
      if (match(buf, /<<-?[ \t]*["'\'']?[A-Za-z_][A-Za-z0-9_]*["'\'']?/)) {
        tok = substr(buf, RSTART, RLENGTH)
        dash = (tok ~ /^<<-/)
        sub(/^<<-?[ \t]*/, "", tok)
        word = unquote(tok)
        inhere = 1
      }
      print buf
    }
    END { if (joining && buf != "") print buf }' | awk '
    { gsub(/&&|\|\||;|\||\$\(|`|\(|\)|\{|\}/, "\n"); print }' | awk '
    {
      line = $0
      sub(/^[ \t\r]+/, "", line)
      while (line ~ /^([A-Za-z_][A-Za-z0-9_]*=[^ \t]*|sudo|command|exec|nohup|time|env|busybox)[ \t]+/) {
        sub(/^[^ \t]+[ \t]+/, "", line)
      }
      sub(/[ \t\r]+$/, "", line)
      if (line != "") print line
    }'
}

# delete_reason COMMAND
# Print the delete command found (rm, rmdir, del, erase, rd, Remove-Item, ri,
# git clean), including inside a cmd or powershell wrapper. Print nothing when
# the command does not delete.
delete_reason() {
  split_commands "$1" | awk '
    {
      line = $0
      first = line
      sub(/[ \t].*/, "", first)
      sub(/.*[\/\\]/, "", first)
      lower = tolower(first)
      sub(/\.exe$/, "", lower)
      rest = line
      sub(/^[^ \t]+[ \t]*/, "", rest)
      if (lower ~ /^(rm|rmdir|del|erase|rd|remove-item|ri)$/) { print first; exit }
      if (lower == "git") {
        r = tolower(rest)
        if (r ~ /^clean([ \t]|$)/) { print "git clean"; exit }
      }
      if (lower ~ /^(cmd|powershell|pwsh)$/) {
        r = tolower(rest)
        if (match(r, /(^|[ \t"'\''])(rm|rmdir|del|erase|rd|remove-item|ri)([ \t"'\'']|$)/)) {
          m = substr(r, RSTART, RLENGTH)
          gsub(/[^a-z-]/, "", m)
          print m
          exit
        }
      }
    }'
}

# force_push_reason COMMAND
# Print the flag or refspec that makes a git push forced (--force,
# --force-with-lease, --force-if-includes, -f, a combined short flag with f,
# or a + refspec). Print nothing otherwise.
force_push_reason() {
  split_commands "$1" | awk '
    {
      line = $0
      gsub(/["'\'']/, "", line)
      n = split(line, t, /[ \t]+/)
      if (t[1] != "git") next
      i = 2
      while (i <= n && t[i] ~ /^-/) {
        if (t[i] == "-C" || t[i] == "-c") i++
        i++
      }
      if (t[i] != "push") next
      for (j = i + 1; j <= n; j++) {
        if (t[j] ~ /^--force($|=)/ || t[j] ~ /^--force-with-lease/ || t[j] == "--force-if-includes" || t[j] ~ /^-[a-zA-Z]*f[a-zA-Z]*$/ || t[j] ~ /^\+/) {
          print t[j]
          exit
        }
      }
    }'
}

# full_sweep_reason COMMAND
# Print the test runner invocation when it would run the whole suite: a known
# runner with no file, directory, pattern or filter after it. Print nothing
# when the run is targeted or the command is not a test runner.
full_sweep_reason() {
  split_commands "$1" | awk '
    function is_target_flag(a) {
      return a ~ /^(-k|-t|-g|-m|-n|--grep|--filter|--testNamePattern|--testPathPattern|--test-name-pattern|--run|--tests|--trait|-Dtest=|--match|--name|--spec|--only)/
    }
    {
      line = $0
      gsub(/["'\'']/, "", line)
      n = split(line, t, /[ \t]+/)
      i = 1
      while (i <= n) {
        if (t[i] ~ /^(npx|bunx)$/) { i++; while (i <= n && t[i] ~ /^-/) i++; continue }
        if ((t[i] == "pnpm" || t[i] == "yarn") && (t[i + 1] == "exec" || t[i + 1] == "dlx")) { i += 2; continue }
        if (t[i] ~ /^(uv|poetry|pipenv|bundle|hatch|pdm)$/ && (t[i + 1] == "run" || t[i + 1] == "exec")) { i += 2; continue }
        if (t[i] ~ /^python[0-9.]*(\.exe)?$/ && t[i + 1] == "-m") { i += 2; continue }
        break
      }
      if (i > n) next
      runner = t[i]
      sub(/.*[\/\\]/, "", runner)
      sub(/\.exe$/, "", runner)
      start = 0
      label = ""
      if (runner ~ /^(npm|yarn|pnpm|bun)$/) {
        j = i + 1
        if (t[j] == "run" || t[j] == "run-script") j++
        if (t[j] == "test" || t[j] == "t" || t[j] == "tst") { start = j + 1; label = runner " " t[j] } else next
      } else if (runner ~ /^(pytest|py\.test|jest|vitest|mocha|ava|tap|rspec|phpunit|ctest|unittest|nose2|karma|playwright|cypress)$/) {
        start = i + 1
        label = runner
      } else if (runner ~ /^(cargo|go|dotnet|mvn|gradle|gradlew|make|rake|mix|swift|flutter|dart|stack)$/ && t[i + 1] == "test") {
        start = i + 2
        label = runner " test"
      } else {
        next
      }
      pos = 0
      for (j = start; j <= n; j++) {
        a = t[j]
        if (a == "" || a == "--") continue
        if (is_target_flag(a)) { pos++; continue }
        if (a ~ /^-/) continue
        if (a ~ /^(run|watch|test|spec)$/) continue
        if (a == "./..." || a == "..." || a == ".") continue
        pos++
      }
      if (pos == 0) { print label; exit }
    }'
}

# generated_page_reason FILE_PATH PROJECT_DIR PATTERNS
# PATTERNS is one shell glob per line; blank lines and # comments are skipped.
# A pattern without a slash is matched against the file name, a pattern with a
# slash against the path relative to PROJECT_DIR. Print the relative path when
# it matches a pattern, nothing otherwise.
generated_page_reason() {
  gp_path=$(printf '%s' "$1" | tr '\\' '/')
  gp_root=$(printf '%s' "$2" | tr '\\' '/')
  gp_root=${gp_root%/}
  gp_rel=$gp_path
  case "$gp_path" in
    "$gp_root"/*) gp_rel=${gp_path#"$gp_root"/} ;;
  esac
  gp_base=${gp_rel##*/}
  printf '%s\n' "$3" | tr -d '\r' | tr '\\' '/' | while IFS= read -r gp_pat; do
    case "$gp_pat" in ''|'#'*) continue ;; esac
    case "$gp_pat" in
      */*)
        case "$gp_rel" in $gp_pat|*/$gp_pat) printf '%s\n' "$gp_rel"; break ;; esac
        ;;
      *)
        case "$gp_base" in $gp_pat) printf '%s\n' "$gp_rel"; break ;; esac
        ;;
    esac
  done
}

# task_tier SUBAGENT_TYPE DESCRIPTION PROMPT
# Print the tier a dispatched task needs: lookup, routine or hard.
# A lookup finds, lists or reads something and has a short prompt. A hard
# task designs, implements, debugs, reviews or plans. Everything else is
# routine.
task_tier() {
  tt_type=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  tt_text=$(printf '%s %s' "$2" "$3" | tr 'A-Z' 'a-z')
  tt_words=$(printf '%s' "$3" | wc -w | tr -d ' ')
  case "$tt_type" in
    explore|claude-code-guide) echo lookup; return 0 ;;
    plan) echo hard; return 0 ;;
  esac
  if printf '%s' "$tt_text" | grep -Eq '(design|architect|refactor|implement|build|debug|fix|review|audit|security|prove|migrat|plan)'; then
    echo hard
    return 0
  fi
  if [ "$tt_words" -le 120 ] && printf '%s' "$tt_text" | grep -Eq '(find|search|locate|list|grep|where is|look up|lookup|which file|read|check whether|does .* exist|count)'; then
    echo lookup
    return 0
  fi
  echo routine
}

# model_rank MODEL
# Print 1 for haiku, 2 for sonnet, 3 for opus, 4 for fable, 0 for unknown.
model_rank() {
  case $(printf '%s' "$1" | tr 'A-Z' 'a-z') in
    *haiku*) echo 1 ;;
    *sonnet*) echo 2 ;;
    *opus*) echo 3 ;;
    *fable*|*mythos*) echo 4 ;;
    *) echo 0 ;;
  esac
}

# agent_model_reason SUBAGENT_TYPE DESCRIPTION PROMPT MODEL
# Print "MODEL_TO_USE TIER" when a dispatch would waste usage: no model was
# set, or the model is heavier than the task's tier needs. Print nothing when
# the dispatch is fine. A lighter model than the tier suggests is allowed.
agent_model_reason() {
  am_tier=$(task_tier "$1" "$2" "$3")
  case "$am_tier" in
    lookup) am_want=haiku; am_rank=1 ;;
    routine) am_want=sonnet; am_rank=2 ;;
    *) am_want=opus; am_rank=3 ;;
  esac
  if [ -z "$4" ]; then
    printf '%s %s\n' "$am_want" "$am_tier"
    return 0
  fi
  if [ "$(model_rank "$4")" -gt "$am_rank" ]; then
    printf '%s %s\n' "$am_want" "$am_tier"
  fi
}

# workflow_model_reason SCRIPT
# Print the number of agent() calls that have no model when a workflow
# script dispatches agents without choosing a model for each. Print nothing
# when every call sets one or the script dispatches none.
workflow_model_reason() {
  wm_calls=$(printf '%s' "$1" | grep -o 'agent(' | wc -l | tr -d ' ')
  wm_models=$(printf '%s' "$1" | grep -o 'model[[:space:]]*:' | wc -l | tr -d ' ')
  [ "$wm_calls" -gt 0 ] || return 0
  if [ "$wm_models" -lt "$wm_calls" ]; then
    echo $((wm_calls - wm_models))
  fi
}

# state_label_reason COMMAND
# Print "gh issue create" when the command creates an issue without a label
# that starts with "state:". Print nothing when the label is there, when the
# command opens the browser form instead, or when it is not an issue creation.
state_label_reason() {
  split_commands "$1" | awk '
    {
      line = $0
      n = split(line, t, /[ \t]+/)
      if (t[1] != "gh" || t[2] != "issue" || t[3] != "create") next
      found = 0
      for (j = 4; j <= n; j++) {
        if (t[j] == "--web" || t[j] == "-w") { found = 1; break }
        v = ""
        if (t[j] == "--label" || t[j] == "-l") v = t[j + 1]
        else if (t[j] ~ /^--label=/) { v = t[j]; sub(/^--label=/, "", v) }
        else if (t[j] ~ /^-l./) { v = t[j]; sub(/^-l/, "", v) }
        gsub(/["'\'']/, "", v)
        if (v ~ /(^|,)state:/) found = 1
      }
      if (!found) { print "gh issue create"; exit }
    }'
}
