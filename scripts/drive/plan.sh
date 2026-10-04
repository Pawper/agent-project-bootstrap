#!/bin/sh
# Gather the project's state and print the proposal the project-drive skill
# would put to a person. This script never acts: it reads, decides, prints.
# The skill posts the proposal and, once approved, pursues it.
#
# Usage, from the project root:
#   sh "$CLAUDE_PLUGIN_ROOT/scripts/drive/plan.sh" [--dry-run] [--snapshot]
# --dry-run is accepted and changes nothing: this script is always dry.
# --snapshot also prints the raw facts the proposal was made from.
#
# Reads .claude/project-drive.json when present: runners (default 2),
# maxAgents (4), maxMinutes (90), queueLogGlob, ownerDecisions.
here=$(dirname "$0")
. "$here/../../hooks/scripts/lib.sh"
. "$here/../../hooks/scripts/session-brief-lib.sh"
. "$here/drive-lib.sh"

show_snapshot=no
for a in "$@"; do case "$a" in --snapshot) show_snapshot=yes ;; esac; done

runners=2; max_agents=4; max_minutes=90; queue_glob=""; owner_phrases=""
if [ -f .claude/project-drive.json ]; then
  cfg=$(cat .claude/project-drive.json)
  n=$(json_number "$cfg" runners); [ -n "$n" ] && runners=$n
  n=$(json_number "$cfg" maxAgents); [ -n "$n" ] && max_agents=$n
  n=$(json_number "$cfg" maxMinutes); [ -n "$n" ] && max_minutes=$n
  queue_glob=$(json_field "$cfg" queueLogGlob)
  owner_phrases=$(printf '%s' "$cfg" | awk 'BEGIN { RS = "\001" } { i = index($0, "\"ownerDecisions\""); if (!i) exit; s = substr($0, i); j = index(s, "["); k = index(s, "]"); if (!j || !k) exit; print substr(s, j + 1, k - j - 1) }' \
    | tr ',' '\n' | sed 's/^[ \t"]*//;s/[ \t"]*$//' | sed '/^$/d')
fi

if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "gh is not available or not signed in; the round cannot read the project."
  echo "stop: unavailable"
  exit 0
fi

tmp=$(mktemp)
tab=$(printf '\t')

# Pull requests: CI state, mergeability, class from the files they touch.
gh pr list --limit 10 --json number,title,mergeable,statusCheckRollup --jq '
  .[] | [
    .number, .title, (.mergeable | ascii_downcase),
    ([.statusCheckRollup[]? | select((.conclusion // "") | test("FAILURE|TIMED_OUT|CANCELLED|ACTION_REQUIRED")) ] | length)
      + ([.statusCheckRollup[]? | select((.state // "") | test("FAILURE|ERROR"))] | length),
    ([.statusCheckRollup[]? | select((.conclusion == null or .conclusion == "") and (.state == null or .state == "PENDING" or .state == "EXPECTED"))] | length),
    ([.statusCheckRollup[]?] | length)
  ] | @tsv' 2>/dev/null | while IFS="$tab" read -r num title merge failed pending total; do
  [ -n "$num" ] || continue
  if [ "${failed:-0}" -gt 0 ]; then ci=red
  elif [ "${pending:-0}" -gt 0 ] || [ "${total:-0}" -eq 0 ]; then ci=pending
  else ci=green; fi
  class=app
  if [ -f scripts/ci/classes.txt ] && [ -f scripts/ci/lib.sh ]; then
    cls=$(sh -c '. scripts/ci/lib.sh; classify_paths "$1" "$(cat scripts/ci/classes.txt)"' sh "$(gh pr diff "$num" --name-only 2>/dev/null)")
    case " $cls " in *" app "*|*" other "*|*" tests "*|*" data "*) class=app ;; *) class=other ;; esac
  fi
  printf 'pr\t%s\t%s\t%s\t%s\t%s\n' "$num" "$title" "$ci" "$merge" "$class"
done >> "$tmp"

# Issues by state, both label spellings, de-duplicated by number.
issues_with() {
  { gh issue list --label "$1" --limit 20 --json number,title,body --jq '.[] | [.number, .title, (.body // "" | gsub("[\\n\\t]"; " "))] | @tsv' 2>/dev/null
    gh issue list --label "$2" --limit 20 --json number,title,body --jq '.[] | [.number, .title, (.body // "" | gsub("[\\n\\t]"; " "))] | @tsv' 2>/dev/null; } | awk -F'\t' '!seen[$1]++'
}
issues_with "state:ready" "state: ready" | while IFS="$tab" read -r num title body; do
  [ -n "$num" ] || continue
  owner=no
  if [ -n "$owner_phrases" ] && [ -n "$(owner_decision_hit "$title $body" "$owner_phrases")" ]; then owner=yes; fi
  printf 'issue\t%s\t%s\tready\t%s\n' "$num" "$title" "$owner"
done >> "$tmp"
issues_with "state:in-progress" "state: in progress" | awk -F'\t' '{ printf "issue\t%s\t%s\tin-progress\tno\n", $1, $2 }' >> "$tmp"
issues_with "state:waiting-on-owner" "state: waiting on owner" | awk -F'\t' '{ printf "issue\t%s\t%s\twaiting-on-owner\tno\n", $1, $2 }' >> "$tmp"

# The audit issue's latest comment, red-main issues, the queue.
audit_issue=$(gh issue list --label audit --state open --limit 1 --json number --jq '.[0].number' 2>/dev/null)
if [ -n "$audit_issue" ]; then
  last=$(gh issue view "$audit_issue" --json comments --jq '.comments[-1].body // ""' 2>/dev/null | tr '\n' ' ' | cut -c1-200)
  [ -n "$last" ] && printf 'audit\t%s\n' "$last" >> "$tmp"
fi
for n in $(gh issue list --label ci-red --state open --limit 5 --json number --jq '.[].number' 2>/dev/null); do printf 'red\t%s\n' "$n" >> "$tmp"; done

queue_state=none
if [ -n "$queue_glob" ]; then
  newest=""; newest_m=0
  for f in $queue_glob; do
    [ -f "$f" ] || continue
    m=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    [ "$m" -gt "$newest_m" ] && { newest_m=$m; newest=$f; }
  done
  if [ -n "$newest" ]; then
    if [ "$(queue_is_stale "$newest_m" "$(date +%s)" "$(tail -n 1 "$newest")")" = yes ]; then queue_state=stale; else queue_state=recent; fi
  fi
fi
printf 'queue\t%s\n' "$queue_state" >> "$tmp"

snapshot=$(cat "$tmp")
[ "$show_snapshot" = yes ] && { echo "snapshot:"; printf '%s\n' "$snapshot"; echo; }
echo "proposal (runners $runners, at most $max_agents agents, at most $max_minutes minutes):"
number_proposal "$(propose_round "$snapshot" "$runners" "$max_agents")"
