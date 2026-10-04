#!/bin/sh
# Tests for the pure part of every script in this repository.
# Run from the repository root with: sh tests/run.sh
# Needs only sh and awk, like the scripts themselves.

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/hooks/scripts/lib.sh"
. "$root/templates/status/lib.sh"
. "$root/templates/scripts/ci/lib.sh"

pass=0
fail=0

# eq NAME EXPECTED ACTUAL
eq() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
    printf 'ok    %s\n' "$1"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      expected: %s\n      actual:   %s\n' "$1" "$2" "$3"
  fi
}

printf '\n# json_field\n'
eq "reads a string field" "ls -la" "$(json_field '{"tool_input":{"command":"ls -la"}}' command)"
eq "undoes escapes" 'echo "hi" && cat a\b' "$(json_field '{"command":"echo \"hi\" && cat a\\b"}' command)"
eq "turns \\n into a newline" "a
b" "$(json_field '{"command":"a\nb"}' command)"
eq "missing key prints nothing" "" "$(json_field '{"x":"y"}' command)"
eq "skips spaces around the colon" "p" "$(json_field '{ "file_path" : "p" }' file_path)"

printf '\n# split_commands\n'
eq "splits on && ; | and ||" "a
b
c
d" "$(split_commands 'a && b; c | d')"
eq "strips env assignments and sudo" "rm x" "$(split_commands 'FOO=1 sudo rm x')"
eq "sees inside a subshell" "echo
rm x" "$(split_commands 'echo $(rm x)')"
eq "joins a backslash continuation" "gh issue create --title x --label state:ready" "$(split_commands 'gh issue create \
  --title x \
  --label state:ready')"
eq "skips a heredoc body" "cat > f.yml <<EOF
echo done" "$(split_commands 'cat > f.yml <<EOF
run: gh issue create --title x
rm -rf nothing
EOF
echo done')"
eq "skips a quoted heredoc body" "cat <<'EOF' > f
ls" "$(split_commands "cat <<'EOF' > f
rm -rf /
EOF
ls")"
eq "a label on a continued line counts" "" "$(state_label_reason 'gh issue create \
  --title "main is red" \
  --label "ci-red,state:ready" \
  --body "x"')"
eq "a create inside a heredoc is not a command" "" "$(state_label_reason 'cat > .github/workflows/ci.yml <<EOF
        run: gh issue create --title x
EOF')"
eq "an rm inside a heredoc is not a command" "" "$(delete_reason 'cat > script.sh <<EOF
rm -rf build
EOF')"
eq "a command after the heredoc still counts" "rm" "$(delete_reason 'cat > s.sh <<EOF
echo hi
EOF
rm -rf build')"

printf '\n# delete_reason\n'
eq "rm" "rm" "$(delete_reason 'rm -rf build')"
eq "rm after cd" "rm" "$(delete_reason 'cd x && rm -r y')"
eq "rm by full path" "rm" "$(delete_reason '/bin/rm x')"
eq "rmdir" "rmdir" "$(delete_reason 'rmdir empty')"
eq "del" "del" "$(delete_reason 'del /q file.txt')"
eq "Remove-Item" "Remove-Item" "$(delete_reason 'Remove-Item -Recurse out')"
eq "Remove-Item inside powershell" "remove-item" "$(delete_reason 'powershell -Command "Remove-Item out"')"
eq "del inside cmd /c" "del" "$(delete_reason 'cmd /c del x.txt')"
eq "git clean" "git clean" "$(delete_reason 'git clean -fdx')"
eq "git status is fine" "" "$(delete_reason 'git status && ls')"
eq "a word containing rm is fine" "" "$(delete_reason 'npm run format')"
eq "git rm is not a delete of history" "" "$(delete_reason 'git rm --cached x')"
eq "removing in a string is fine" "" "$(delete_reason 'echo "do not rm this"')"

printf '\n# force_push_reason\n'
eq "--force" "--force" "$(force_push_reason 'git push --force origin main')"
eq "--force-with-lease" "--force-with-lease=main" "$(force_push_reason 'git push --force-with-lease=main origin main')"
eq "-f" "-f" "$(force_push_reason 'git push -f')"
eq "combined short flags" "-uf" "$(force_push_reason 'git push -uf origin x')"
eq "plus refspec" "+main" "$(force_push_reason 'git push origin +main')"
eq "quoted plus refspec" "+main" "$(force_push_reason "git push origin '+main'")"
eq "after git -C" "--force" "$(force_push_reason 'git -C /repo push --force')"
eq "plain push is fine" "" "$(force_push_reason 'git push -u origin feature')"
eq "a commit named force is fine" "" "$(force_push_reason 'git commit -m "force"')"
eq "push in a later command" "-f" "$(force_push_reason 'git fetch && git push -f')"

printf '\n# full_sweep_reason\n'
eq "bare pytest" "pytest" "$(full_sweep_reason 'pytest')"
eq "pytest with options only" "pytest" "$(full_sweep_reason 'pytest -q --maxfail=1')"
eq "pytest with a file is fine" "" "$(full_sweep_reason 'pytest tests/test_a.py')"
eq "pytest with -k is fine" "" "$(full_sweep_reason 'pytest -k login')"
eq "npm test" "npm test" "$(full_sweep_reason 'npm test')"
eq "npm run test" "npm test" "$(full_sweep_reason 'npm run test -- --coverage')"
eq "npm test with a file is fine" "" "$(full_sweep_reason 'npm test -- src/a.test.ts')"
eq "yarn test" "yarn test" "$(full_sweep_reason 'yarn test')"
eq "pnpm test" "pnpm test" "$(full_sweep_reason 'pnpm test')"
eq "npx jest" "jest" "$(full_sweep_reason 'npx jest')"
eq "npx vitest run with a file is fine" "" "$(full_sweep_reason 'npx vitest run src/a.test.ts')"
eq "vitest run alone" "vitest" "$(full_sweep_reason 'vitest run')"
eq "go test ./..." "go test" "$(full_sweep_reason 'go test ./...')"
eq "go test one package is fine" "" "$(full_sweep_reason 'go test ./pkg/auth')"
eq "cargo test" "cargo test" "$(full_sweep_reason 'cargo test')"
eq "cargo test with a filter is fine" "" "$(full_sweep_reason 'cargo test parse_date')"
eq "dotnet test" "dotnet test" "$(full_sweep_reason 'dotnet test')"
eq "dotnet test with --filter is fine" "" "$(full_sweep_reason 'dotnet test --filter Name~Login')"
eq "python -m pytest" "pytest" "$(full_sweep_reason 'python -m pytest')"
eq "uv run pytest" "pytest" "$(full_sweep_reason 'uv run pytest')"
eq "a sweep after cd" "pytest" "$(full_sweep_reason 'cd app && pytest')"
eq "npm run build is fine" "" "$(full_sweep_reason 'npm run build')"
eq "ls is fine" "" "$(full_sweep_reason 'ls tests')"

printf '\n# generated_page_reason\n'
pages="# comment
STATUS.md
docs/generated/*"
eq "matches by file name" "STATUS.md" "$(generated_page_reason /proj/STATUS.md /proj "$pages")"
eq "matches a Windows path" "STATUS.md" "$(generated_page_reason 'C:\proj\STATUS.md' 'C:\proj' "$pages")"
eq "matches a path pattern" "docs/generated/api.md" "$(generated_page_reason /proj/docs/generated/api.md /proj "$pages")"
eq "matches a path pattern when the root is unknown" "/other/docs/generated/api.md" "$(generated_page_reason /other/docs/generated/api.md /proj "$pages")"
eq "a stub is fine" "" "$(generated_page_reason /proj/status/stubs/x.md /proj "$pages")"
eq "an unrelated file is fine" "" "$(generated_page_reason /proj/src/a.ts /proj "$pages")"
eq "a comment line never matches" "" "$(generated_page_reason '/proj/# comment' /proj "$pages")"

printf '\n# state_label_reason\n'
eq "no label" "gh issue create" "$(state_label_reason 'gh issue create --title x --body y')"
eq "a label without a state" "gh issue create" "$(state_label_reason 'gh issue create -t x -l bug')"
eq "--label state:" "" "$(state_label_reason 'gh issue create -t x --label state:ready')"
eq "-l with a list" "" "$(state_label_reason 'gh issue create -t x -l bug,state:parked')"
eq "--label= form" "" "$(state_label_reason 'gh issue create --label=state:dated -t x')"
eq "quoted label" "" "$(state_label_reason "gh issue create -l 'state:waiting-on-owner' -t x")"
eq "--web opens the form, which requires it" "" "$(state_label_reason 'gh issue create --web')"
eq "a quoted list with spaces" "" "$(state_label_reason 'gh issue create --title x --label "ci-red, state: ready" --body y')"
eq "a quoted list with spaces on a continued line" "" "$(state_label_reason 'gh issue create \
  --title "main is red" \
  --label "ci-red, state: ready" \
  --body y')"
eq "a quoted label with a space but no state" "gh issue create" "$(state_label_reason 'gh issue create -l "needs triage" -t x')"
eq "gh issue list is fine" "" "$(state_label_reason 'gh issue list')"
eq "create in a later command" "gh issue create" "$(state_label_reason 'git push && gh issue create -t x')"

printf '\n# batch_merge_reason\n'
eq "three PRs with no flag" "3" "$(batch_merge_reason 'sh scripts/ci/merge-queue.sh 41 42 45')"
eq "three PRs with --batch" "" "$(batch_merge_reason 'sh scripts/ci/merge-queue.sh --batch 41 42 45')"
eq "three PRs with --serial" "" "$(batch_merge_reason 'sh scripts/ci/merge-queue.sh --serial 41 42 45')"
eq "two PRs with no flag" "" "$(batch_merge_reason 'sh scripts/ci/merge-queue.sh 41 42')"
eq "one PR as before" "" "$(batch_merge_reason 'sh scripts/ci/merge-queue.sh 41 main')"
eq "a chained serial run after cd" "4" "$(batch_merge_reason 'cd app && sh ./scripts/ci/merge-queue.sh 1 2 3 4')"
eq "another script with numbers is fine" "" "$(batch_merge_reason 'sh scripts/other.sh 1 2 3')"

printf '\n# batch helpers\n'
. "$root/templates/scripts/ci/batch-lib.sh"
eq "order kept, repeats dropped, words ignored" "41
42
45" "$(batch_order 41 42 41 x 45 | tr '\n' ' ' | sed 's/ $//' | tr ' ' '\n')"
eq "test files from a diff" "tests/unit/a.test.ts
src/b.spec.tsx" "$(tests_for_diff 'src/a.ts
tests/unit/a.test.ts
src/b.spec.tsx
docs/x.md
e2e/login.spec.ts
tests/e2e/flow.test.ts')"
eq "no test files, nothing" "" "$(tests_for_diff 'src/a.ts
README.md')"
eq "branch name for the day" "batch-2026-10-03" "$(batch_branch_name 2026-10-03)"
eq "second batch of the day" "batch-2026-10-03-2" "$(batch_branch_name 2026-10-03 2)"
eq "batch PR body" "- #41 Add retries. Closes #41
- #45 Fix the parser. Closes #45" "$(batch_pr_body "$(printf '41\tAdd retries\n45\tFix the parser\n')" | tail -n 2)"
eq "one line per PR" "#13 dropped: conflicts with the batch so far" "$(batch_line 13 dropped 'conflicts with the batch so far')"
eq "one line without a reason" "#12 merged into the batch" "$(batch_line 12 'merged into the batch')"

printf '\n# task_tier and agent_model_reason\n'
eq "Explore is a lookup" "lookup" "$(task_tier Explore 'Find config' 'Find where the port is set')"
eq "Plan is hard" "hard" "$(task_tier Plan 'Plan it' 'Plan the cache')"
eq "a short find is a lookup" "lookup" "$(task_tier general-purpose 'Find the parser' 'Find which file parses dates and report the path')"
eq "implement is hard" "hard" "$(task_tier general-purpose 'Add retries' 'Implement retries in the client')"
eq "a long find is routine" "routine" "$(task_tier general-purpose 'Survey' "$(awk 'BEGIN { for (i = 0; i < 130; i++) printf "find word "; }')")"
eq "a summary is routine" "routine" "$(task_tier general-purpose 'Summarize' 'Summarize the release notes in five lines')"
eq "no model on a lookup" "haiku lookup" "$(agent_model_reason Explore 'Find x' 'Find x' '')"
eq "no model on hard work" "opus hard" "$(agent_model_reason general-purpose 'Fix the bug' 'Debug the crash' '')"
eq "opus on a lookup is heavier than needed" "haiku lookup" "$(agent_model_reason Explore 'Find x' 'Find x' opus)"
eq "fable on routine work is heavier than needed" "sonnet routine" "$(agent_model_reason general-purpose 'Summarize' 'Summarize the notes' fable)"
eq "haiku on a lookup is fine" "" "$(agent_model_reason Explore 'Find x' 'Find x' haiku)"
eq "sonnet on routine is fine" "" "$(agent_model_reason general-purpose 'Summarize' 'Summarize the notes' sonnet)"
eq "a lighter model is always fine" "" "$(agent_model_reason general-purpose 'Fix it' 'Debug the crash' haiku)"
eq "opus on hard work is fine" "" "$(agent_model_reason Plan 'Plan it' 'Plan the cache' opus)"
eq "model ranks" "1 2 3 4 0" "$(printf '%s %s %s %s %s' "$(model_rank haiku)" "$(model_rank claude-sonnet-5-5)" "$(model_rank Opus)" "$(model_rank fable)" "$(model_rank '')")"

printf '\n# workflow_model_reason\n'
eq "every call has a model" "" "$(workflow_model_reason 'await agent("a", {model: "haiku"}); await agent("b", { model : "sonnet" })')"
eq "one call without a model" "1" "$(workflow_model_reason 'await agent("a", {model: "haiku"}); await agent("b", {label: "x"})')"
eq "no agents, nothing" "" "$(workflow_model_reason 'return 1')"

printf '\n# status page\n'
fixtures=$(mktemp -d)
mkdir -p "$fixtures/stubs"
printf 'name: Sign in\nstate: done\nissue: #3\nnote: Password and magic link.\n' > "$fixtures/stubs/sign-in.md"
printf 'name: Billing\nstate: blocked\nissue: #9\nnote: Waiting on the payment provider.\n' > "$fixtures/stubs/billing.md"
printf 'state: in progress\n' > "$fixtures/stubs/export.md"
printf '# comment\nDatabase: running\nMail: degraded\n' > "$fixtures/services.txt"
eq "stub_field reads a value" "Sign in" "$(stub_field "$fixtures/stubs/sign-in.md" name)"
eq "stub_field missing key prints nothing" "" "$(stub_field "$fixtures/stubs/sign-in.md" owner)"
page=$(render_status "$fixtures/stubs" "$fixtures/services.txt")
eq "one row per feature, sorted by file" "| Billing | blocked | #9 | Waiting on the payment provider. |
| export | in progress |  |  |
| Sign in | done | #3 | Password and magic link. |" "$(printf '%s\n' "$page" | grep '^| ' | grep -v -e 'Feature' -e 'Service' -e 'Database' -e 'Mail')"
eq "services table" "| Database | running |
| Mail | degraded |" "$(printf '%s\n' "$page" | grep -e '^| Database' -e '^| Mail')"
eq "not-done list leaves out done" "- Billing (blocked)
- export (in progress)" "$(printf '%s\n' "$page" | grep '^- ')"
eq "no services file, no services section" "" "$(render_status "$fixtures/stubs" "$fixtures/none.txt" | grep '^## Services')"
printf 'name: Only\nstate: done\n' > "$fixtures/stubs/billing.md"
printf 'name: Only\nstate: done\n' > "$fixtures/stubs/sign-in.md"
printf 'name: Only\nstate: done\n' > "$fixtures/stubs/export.md"
eq "all done says so" "Nothing. Every feature is done." "$(render_status "$fixtures/stubs" | tail -n 1)"

printf '\n# status check\n'
proj=$(mktemp -d)
cp -R "$root/templates/status" "$proj/status"
check=$(cd "$proj" && sh status/check.sh 2>&1; echo "exit $?")
eq "missing page fails" "STATUS.md is missing: run sh status/build.sh and commit the result.
exit 1" "$check"
(cd "$proj" && sh status/build.sh >/dev/null)
check=$(cd "$proj" && sh status/check.sh 2>&1; echo "exit $?")
eq "fresh page passes" "STATUS.md is current.
exit 0" "$check"
printf 'name: New\nstate: not started\n' > "$proj/status/stubs/new.md"
check=$(cd "$proj" && sh status/check.sh 2>&1; echo "exit $?")
eq "stale page fails" "STATUS.md is stale: run sh status/build.sh and commit the result.
exit 1" "$check"

printf '\n# classify_paths\n'
rules=$(cat "$root/templates/scripts/ci/classes.txt")
eq "app" "app" "$(classify_paths 'src/a.ts' "$rules")"
eq "deep path under src" "app" "$(classify_paths 'src/deep/er/a.ts' "$rules")"
eq "docs" "docs" "$(classify_paths 'README.md' "$rules")"
eq "a status stub is status, not docs" "status" "$(classify_paths 'status/stubs/a.md' "$rules")"
eq "workflow is ci" "ci" "$(classify_paths '.github/workflows/ci.yml' "$rules")"
eq "several classes, sorted, unique" "app docs tests" "$(classify_paths 'src/a.ts
docs/x.md
tests/a_test.py
src/b.ts' "$rules")"
eq "unknown path is other" "other" "$(classify_paths 'weird.bin' "$rules")"
eq "Windows separators are fine" "app" "$(classify_paths 'src\a.ts' "$rules")"
eq "empty input, no classes" "" "$(classify_paths '' "$rules")"

printf '\n# needs_rerun\n'
eq "no overlap merges" "no" "$(needs_rerun 'app' 'docs')"
eq "overlap reruns" "yes" "$(needs_rerun 'app tests' 'data app')"
eq "other on main reruns" "yes" "$(needs_rerun 'app' 'other')"
eq "other on the PR reruns" "yes" "$(needs_rerun 'other' 'docs')"
eq "ci on main reruns" "yes" "$(needs_rerun 'app' 'ci')"
eq "main unchanged merges" "no" "$(needs_rerun 'app' '')"

printf '\n# state_label_from_body\n'
body="### State

waiting on owner

### Outcome

Something."
eq "reads the field" "state:waiting-on-owner" "$(state_label_from_body "$body")"
eq "ready" "state:ready" "$(state_label_from_body '### State
Ready')"
eq "after launch" "state:after-launch" "$(state_label_from_body '### State
After launch')"
eq "no field, no label" "" "$(state_label_from_body '### Outcome
x')"
eq "empty response, no label" "" "$(state_label_from_body '### State

_No response_')"
eq "CRLF body" "state:parked" "$(state_label_from_body "$(printf '### State\r\n\r\nparked\r\n')")"

printf '\n# spec_check_reason\n'
eq "src with its spec is fine" "" "$(spec_check_reason 'src/auth.ts
specs/sign-in/spec.md')"
eq "src without a spec is missing" "missing" "$(spec_check_reason 'src/auth.ts
README.md')"
eq "the constitution does not count" "missing" "$(spec_check_reason 'src/auth.ts
specs/constitution.md')"
eq "no src, nothing to check" "" "$(spec_check_reason 'docs/a.md
specs/constitution.md')"
eq "many spec folders warns" "many 2" "$(spec_check_reason 'src/a.ts
specs/sign-in/spec.md
specs/billing/spec.md')"
eq "a spec class" "specs" "$(classify_paths 'specs/sign-in/spec.md' "$rules")"

printf '\n# board mappings\n'
eq "label to state name" "Waiting on owner" "$(state_name_from_label state:waiting-on-owner)"
eq "ready label" "Ready" "$(state_name_from_label state:ready)"
eq "not a state label" "" "$(state_name_from_label bug)"
eq "state name to label" "state:waiting-on-a-service" "$(label_from_state_name 'Waiting on a service')"
eq "round trip" "After launch" "$(state_name_from_label "$(label_from_state_name 'After launch')")"
eq "first state label in a list" "state:parked" "$(state_label_in 'bug, state:parked,task')"
eq "no state label in a list" "" "$(state_label_in 'bug,task')"
eq "status for in progress" "In Progress" "$(status_for 'In progress' false)"
eq "status for ready" "Todo" "$(status_for Ready false)"
eq "status for parked" "Todo" "$(status_for Parked false)"
eq "status for a closed issue is Done whatever the state" "Done" "$(status_for 'In progress' true)"

printf '\n# audit helpers\n'
eq "issues without a state label" "12
15" "$(issues_without_state '12 bug,task
14 state:ready,task
15
16 task,state:parked')"
eq "issue refs, unique, in order" "4
12" "$(issue_refs 'Closes #4 and fixes #12; see #4 again')"
eq "no refs, nothing" "" "$(issue_refs 'no numbers here')"
eq "clean audit says nothing" "" "$(audit_comment '' '')"
eq "missing only" "Open issues with no State label:
- #12
- #15" "$(audit_comment '12
15' '')"
eq "stale only" "Issues still open and labeled ready after their PR merged:
- #4 (merged in #30)" "$(audit_comment '' '30 4')"
eq "both, with a blank line between" "Open issues with no State label:
- #12

Issues still open and labeled ready after their PR merged:
- #4 (merged in #30)" "$(audit_comment '12' '30 4')"
eq "red main comes first" "Main is red and the issue is still open:
- #77

Open issues with no State label:
- #12" "$(audit_comment '12' '' '77')"
eq "red only" "Main is red and the issue is still open:
- #77" "$(audit_comment '' '' '77')"

printf '\n# setup_check_reason and has_crlf\n'
setup_pats=$(cat "$root/templates/scripts/ci/setup-paths.txt")
eq "migration without SETUP.md" "migrations/0002_x.sql" "$(setup_check_reason 'src/a.ts
migrations/0002_x.sql' "$setup_pats")"
eq "migration with SETUP.md is fine" "" "$(setup_check_reason 'migrations/0002_x.sql
SETUP.md' "$setup_pats")"
eq "no setup file, nothing to check" "" "$(setup_check_reason 'src/a.ts
docs/b.md' "$setup_pats")"
eq "workflow change counts as setup" ".github/workflows/ci.yml" "$(setup_check_reason '.github/workflows/ci.yml' "$setup_pats")"
own_pats="manual docs/setup.md
$setup_pats"
eq "the manual defaults to SETUP.md" "SETUP.md" "$(setup_manual "$setup_pats")"
eq "a manual line names the project's own" "docs/setup.md" "$(setup_manual "$own_pats")"
eq "the project's own manual satisfies the check" "" "$(setup_check_reason 'migrations/0002_x.sql
docs/setup.md' "$own_pats")"
eq "SETUP.md no longer counts when the manual is elsewhere" "migrations/0002_x.sql" "$(setup_check_reason 'migrations/0002_x.sql
SETUP.md' "$own_pats")"
eq "crlf found" "yes" "$(has_crlf "$(printf 'a\r\nb')")"
eq "lf only" "" "$(has_crlf "$(printf 'a\nb')")"

printf '\n# owner console (node)\n'
if command -v node >/dev/null 2>&1; then
  if node --test --test-reporter tap "$root"/console/test/*.test.js >"$root/tests/console.log" 2>&1; then
    node_count=$(sed -n 's/^# pass \([0-9]*\).*/\1/p' "$root/tests/console.log" | tr -d '\r')
    pass=$((pass + ${node_count:-0}))
    printf 'ok    %s console tests\n' "${node_count:-0}"
  else
    fail=$((fail + 1))
    printf 'FAIL  console tests, see tests/console.log\n'
    grep -E '^not ok|^# (fail|pass)' "$root/tests/console.log"
  fi
  mv "$root/tests/console.log" "$root/tests/console.log.last"
else
  printf 'skip  node is not installed, so the console tests did not run\n'
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
