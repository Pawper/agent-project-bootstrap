#!/bin/sh
# Bring a project's copies of the plugin's scripts up to date with the
# installed plugin. A project copies the templates once, at bootstrap, and
# nothing refreshes them, so a project can run a merge queue from weeks ago
# while the plugin has moved on: one project asked for a batch mode its own
# copy of the queue did not have.
#
# Usage, from the project root:
#   sh "$CLAUDE_PLUGIN_ROOT/scripts/sync/sync-templates.sh"          report only
#   sh "$CLAUDE_PLUGIN_ROOT/scripts/sync/sync-templates.sh" --apply  update, on a new branch
#
# What it does with each kind of file:
#   - Plugin-owned scripts and workflows (templates/OWNED.txt): reported when
#     missing or different; with --apply, written from the plugin.
#   - Config with defaults: added when missing; never replaced.
#   - The project's own files (ci.yml, .gitattributes, .gitignore):
#     never touched; it reports the jobs and lines the template has that
#     the project's copy lacks, for a person to merge by hand.
#
# --apply needs a clean working tree. It makes a branch named
# template-sync-<date> from the current commit, writes the files there and
# commits them, so every change is a reviewable diff in a pull request and
# the old versions stay in git. It does not push.
here=$(dirname "$0")
. "$here/sync-lib.sh"
plugin=$(cd "$here/../.." && pwd)
tpl="$plugin/templates"
apply=no; [ "$1" = "--apply" ] && apply=yes

git rev-parse --git-dir >/dev/null 2>&1 || { echo "Run this from the project's root, inside its git repository." >&2; exit 2; }
version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$plugin/.claude-plugin/plugin.json" | head -n 1)
owned=$(cat "$tpl/OWNED.txt")

changed=""; missing=""; current=0
for p in $(owned_paths "$owned"); do
  if [ ! -f "$p" ]; then missing="$missing $p"; continue; fi
  if [ "$(same_text "$(cat "$p")" "$(cat "$tpl/$p")")" = yes ]; then current=$((current + 1)); else changed="$changed $p"; fi
done
defaults=""
for p in $(default_paths "$owned"); do [ -f "$p" ] || defaults="$defaults $p"; done

echo "Plugin $version. Plugin-owned files here: $current current, $(printf '%s' "$changed" | wc -w | tr -d ' ') older or edited, $(printf '%s' "$missing" | wc -w | tr -d ' ') missing."
for p in $changed; do
  # A file committed more than once has been edited in this project since
  # it was copied; the refresh would replace that edit, so say so.
  n=$(git log --oneline -- "$p" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${n:-0}" -gt 1 ]; then echo "  differs:  $p (edited here in $((n - 1)) later commit(s); check that diff before merging)"
  else echo "  differs:  $p"; fi
done
for p in $missing; do echo "  missing:  $p"; done
for p in $defaults; do echo "  new config, would be added with its defaults: $p"; done

# The project's own files: report what the template gained.
if [ -f .github/workflows/ci.yml ]; then
  jobs=$(missing_jobs "$(cat "$tpl/.github/workflows/ci.yml")" "$(cat .github/workflows/ci.yml)")
  [ -n "$jobs" ] && echo "  ci.yml is yours; the template has jobs it lacks: $(printf '%s' "$jobs" | tr '\n' ' ')(copy them from $tpl/.github/workflows/ci.yml and add each to CI passed)"
fi
for f in .gitattributes .gitignore; do
  [ -f "$f" ] || continue
  lines=$(missing_lines "$(cat "$tpl/$f")" "$(cat "$f")")
  [ -n "$lines" ] && echo "  $f is yours; the template has lines it lacks: $(printf '%s' "$lines" | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
done

work=$(printf '%s%s%s' "$changed" "$missing" "$defaults" | tr -d ' ')
if [ -z "$work" ]; then echo "Everything the plugin owns is current."; exit 0; fi
if [ "$apply" = no ]; then echo "Nothing was changed. Add --apply to write these on a new branch."; exit 0; fi

[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "The working tree has uncommitted changes; commit or move them aside first." >&2; exit 1; }
branch="template-sync-$(date +%Y-%m-%d)"
git show-ref --verify --quiet "refs/heads/$branch" && branch="$branch-$(date +%H%M)"
git checkout -q -b "$branch"
for p in $changed $missing $defaults; do
  mkdir -p "$(dirname "$p")"
  cp "$tpl/$p" "$p"
  case "$p" in *.sh) chmod +x "$p" 2>/dev/null || true ;; esac
done
git add -- $changed $missing $defaults
git commit -q -m "Sync the plugin's scripts and workflows to project-bootstrap $version" -m "Plugin-owned files were brought up to date with the installed plugin; config files that did not exist were added with their defaults. Files the project owns were not touched."
echo "Committed on branch $branch. Review the diff, then push it and open a pull request."
