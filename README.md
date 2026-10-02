# agent-project-bootstrap

A Claude Code plugin for standing up a project so many coding agents can work in it at once without colliding.

## Why

Rules written for one agent become pathologies when thirty follow them at once. One agent appending a line to a status page is tidy; thirty doing it is a merge conflict on every PR. One agent running the full test suite before it pushes is careful; thirty doing it is a merge queue that waits an hour per change. The codebase is the one surface every agent must write to, so anything that lives there is something they all collide on.

The fix is to decide two things before the first feature agent runs:

- **Homes.** One place for each kind of thing. Work lives in issues, status on the board, orientation on one generated page, data in the database, research outside the repo. Nothing goes anywhere else.
- **Enforcement.** An instruction decays under load. For every rule there is a hook that blocks the dangerous command, a CI check that fails on drift, a required field at filing, or an audit that speaks only when something is wrong. A rule with none of those will not hold.

This repository holds the skill that walks through those decisions, the hooks that enforce the rules, and templates for every file the skill creates.

## The stack it was built for, and yours

The plugin has a preferred stack: GitHub for issues, the project board and Actions, the `gh` CLI in its scripts, Claude Code for the hooks, and a plain Markdown spec folder per feature. It is honest about that. When a project uses something else, the skill says so once and then adapts: every home and every rule is about a kind of place, not a product, so the agent proposes the nearest equivalent and keeps the rule.

| Preferred | If you use | The agent proposes |
|---|---|---|
| GitHub issues, one per task | GitLab, Jira, Linear, a plain tracker | Their issue with a required State field or label; the PR or MR still closes it |
| GitHub project board with a State field | GitLab boards, Jira board, Linear views | A board grouped by State fed by the tracker's own automation, never a hand-kept page |
| GitHub Actions | GitLab CI, Buildkite, Jenkins, CircleCI | The same jobs: classify, per-class, one summary check, full run on main, red run opens an issue |
| `gh` in scripts | `glab`, a REST call, the tracker's CLI | The same scripts with the calls swapped; the pure parts are tool-free and tested |
| Claude Code hooks | Another agent runtime | That runtime's pre-command hook if it has one; otherwise a CI check or a git hook, and the agent says the rule is weaker |
| Spec folder per feature, by hand or with GitHub's spec-kit | Any spec tool, or none | A folder per feature with a constitution and a spec file; the CI check holds either way |

What never changes: one home per kind of thing, nothing appended to a shared page, every rule has something that enforces it, and the full suite gates main rather than the PR.

## What is in the box

| Piece | Where | What it does |
|---|---|---|
| The skill | `skills/project-bootstrap/SKILL.md` | The design: homes, rules, enforcement, CI from day one, and the outputs in order |
| The hooks | `hooks/hooks.json`, `hooks/scripts/` | Six PreToolUse hooks that block the dangerous commands and the wasteful dispatches |
| The templates | `templates/` | Issue template, CLAUDE.md and AGENTS.md, setup and notice skeletons, the status page and its scripts, the CI workflow, the merge queue, the board setup, the nightly audit |
| The tests | `tests/run.sh` | One test per pure function in every script |

## Install

### As a plugin

Inside a Claude Code session:

```text
/plugin marketplace add Pawper/agent-project-bootstrap
/plugin install project-bootstrap@agent-project-bootstrap
```

Or from a shell, which also works in a setup script:

```bash
claude plugin marketplace add Pawper/agent-project-bootstrap
```

```bash
claude plugin install project-bootstrap@agent-project-bootstrap
```

Pick the scope you want when asked. User scope gives you the skill and the hooks in every project. Project scope writes the plugin into the repository's `.claude/settings.json` so every collaborator gets the hooks too, which is the point.

To try a local checkout without installing it:

```bash
claude --plugin-dir /path/to/agent-project-bootstrap
```

### Copy the folder

If you want only the skill, copy `skills/project-bootstrap/` into `~/.claude/skills/` to use it everywhere, or into a project's `.claude/skills/`. The hooks do not come along that way; to get them without the plugin, copy `hooks/scripts/` into the project and point `.claude/settings.json` at the scripts with the same five entries as `hooks/hooks.json`, replacing `${CLAUDE_PLUGIN_ROOT}` with `${CLAUDE_PROJECT_DIR}`.

## Use

Start a session in a new or struggling repository and say what you want:

```text
/project-bootstrap set this project up for many agents
```

The skill walks the homes table, writes the rules into CLAUDE.md and AGENTS.md, and copies the templates in. Replace every CAPITALIZED placeholder, then run two scripts:

```bash
sh scripts/board.sh OWNER OWNER/REPO
```

```bash
sh status/build.sh
```

Then switch on the board's built-in workflows by hand, as described below, and let the first feature agent run.

## The user flow, start to finish

This is what a person does with the plugin, from install to the first feature agent, and what runs on its own after that.

1. **Install.** In a Claude Code session, add the marketplace and install the plugin with the two commands above. Pick project scope so every collaborator gets the hooks. From this moment the six hooks are live: deletes, forced pushes, full test sweeps, direct edits to generated pages, issues without a State label, and agent dispatches without a fitting model are refused with one sentence each.
2. **Run the skill.** In a new or struggling repository, say `/project-bootstrap set this project up for many agents`. The skill looks at the repository first, then asks a short survey for what it could not tell: new or existing project, where issues and CI live, which agent runtimes, the one-file test command, which pages are generated, the spec tool, runners, and where the work folder goes. It records the answers under a Stack heading in CLAUDE.md, walks the homes table, writes the rules into CLAUDE.md and AGENTS.md, and copies the templates in, adapted to the answers. Replace every capitalized placeholder that is left.
3. **Create the board and labels.** Run `sh scripts/board.sh OWNER OWNER/REPO`. It creates the seven state labels, the project board, its State field with the seven values, and links the repository.
4. **Two settings GitHub cannot script.** In the board's Workflows tab, switch on the four built-in workflows listed under The project board. In branch protection on main, require exactly one check, `CI passed`, and leave "require branches to be up to date" off, as described under Branch protection on main.
5. **Build the status page once.** Run `sh status/build.sh` and commit STATUS.md. From here on CI fails any PR that leaves the page stale, and the hook refuses hand edits to it.
6. **Write the constitution and the first spec.** Fill in `specs/constitution.md` once, then copy `specs/FEATURE/` to `specs/<feature>/` for the first feature. If you use spec kit, run it inside that folder; the templates are plain Markdown and do not depend on it. From here on CI fails any PR that changes `src/` without a change in a spec folder.
7. **Day to day.** Each task starts as an issue with a State, filed from the template or with `gh issue create --label state:ready`, and the coordinator sets the board field with `scripts/state.sh`. Agents work in worktrees, run only the tests for the files they changed, and open PRs. CI runs only the classes a PR touches and reports once through `CI passed`. The merge queue script merges a green PR without a re-run when main moved outside its classes. The full suite runs on main after every merge and opens a `ci-red` issue when it fails. Every night the audit comments on the tracking issue only when an issue has no State or a merged PR left one stale.
8. **When a hook refuses something.** The message says what was blocked and what to do instead; do that. A project that really needs an exception changes `.claude/generated-pages.txt` or disables the plugin for that repository. Nobody works around a hook.

## What each hook blocks and why

Every hook reads the tool call before it runs, and when it refuses, it prints one plain sentence saying what it blocked and what to do instead. The scripts are POSIX shell with awk and nothing else, so they run under Git Bash on Windows and on macOS and Linux as they are.

**Deletes.** `rm`, `rmdir`, `del`, `erase`, `rd`, `Remove-Item`, `ri`, and `git clean`, including inside a `cmd /c` or `powershell -Command` wrapper. With many agents, a delete is the one change nobody else can undo, and a file one agent considers dead is often the file another is reading. The rule is never delete; move aside. The hook says so and suggests `git mv`.

**Forced pushes.** `git push` with `--force`, `--force-with-lease`, `--force-if-includes`, `-f` in any combined flag, or a `+` refspec. A rewritten branch pulls the ground out from every worktree based on it. Push a new commit instead, or start a new branch.

**Full test sweeps.** A bare test command with no file, directory or filter after it: `pytest`, `npm test`, `yarn test`, `pnpm test`, `jest`, `vitest`, `mocha`, `go test ./...`, `cargo test`, `dotnet test` and the common launchers in front of them such as `npx`, `uv run` and `python -m`. Tests on a PR prove the change and run per file. The full suite is the gate on main, run once by CI after the merge, not thirty times before it.

**Direct edits to generated pages.** An `Edit`, `Write` or `MultiEdit` whose path matches a line in the project's `.claude/generated-pages.txt`. When that file is absent the list is just `STATUS.md`. A generated page is built from stubs; a hand edit is lost on the next build and is the shared file every agent would otherwise append to. The hook points at the stub and the build script.

**Issues without a State.** `gh issue create` with no `--label state:...`. The board and the nightly audit can only be trusted if every issue carries its state from the moment it is filed, and filing is the moment the agent already knows it. `gh issue create --web` is allowed because the issue form requires the field itself.

**Agents dispatched without a fitting model.** An `Agent` call with no `model`, or with a model heavier than its task needs, and a `Workflow` script with an `agent()` call that sets no model. Thirty agents each fanning out subagents on the heaviest model is the fastest way to spend a usage budget on lookups. The hook sorts the task by its type, description and prompt into a lookup (haiku), routine work (sonnet) or hard work (opus), and refuses when the model is missing or heavier than that. A lighter model than suggested is always allowed. Agents inherit the session's effort level and there is no per-agent effort setting, so the message reports the current effort and says to lower it before a long lookup.

Sample of what a refusal looks like, from the delete hook:

```text
Blocked `rm` because this project never deletes files; move them aside instead, for example `git mv path aside/path` or `mv path path.aside`.
```

If a hook refuses a command you believe is right, the answer is still the one in the message. A project that needs an exception should change the list in `.claude/generated-pages.txt` or disable the plugin for that repository, not work around the hook.

## The templates

All of them live in `templates/` and are meant to be copied into the project root as they are.

- `.github/ISSUE_TEMPLATE/task.yml`: one issue per task, with a required State dropdown. `config.yml` turns off blank issues.
- `.github/workflows/state-label.yml`: when an issue is opened or edited, sets the `state:` label to match the State field and removes the others.
- `CLAUDE.md` and `AGENTS.md`: the homes table, the rules, and a table of what enforces each one. Keep them identical.
- `SETUP.md`: the one manual. Configuration by name, first run, migrations run, services.
- `NOTICE.md`: credit for borrowed code, one line per item.
- `status/`: one stub per feature in `stubs/`, a `services.txt`, and `lib.sh`, `build.sh` and `check.sh`. The build writes `STATUS.md`; the check fails when the page does not match the stubs, and CI runs it on every PR.
- `specs/constitution.md` and `specs/FEATURE/spec.md`: the rules every spec obeys, written once, and the skeleton for one feature's spec. One folder per feature, so two PRs never edit the same spec file.
- `scripts/ci/spec-check.sh`: fails a PR that changes `src/` without a change in a feature's spec folder. The constitution does not count, so nobody pokes it to satisfy the check. More than one spec folder in a PR is a warning that the task was too big, not a failure.
- `scripts/ci/setup-check.sh` and `setup-paths.txt`: fails a PR that changes a setup file (migrations, the example env file, the container files, the workflows, the dependency manifests) without a change to `SETUP.md`.
- `scripts/ci/line-endings.sh` and `.gitattributes`: the attributes file forces LF everywhere; the check fails on any tracked text file that still has CRLF.
- `scripts/ci/classes.txt`: which paths belong to which change class.
- `scripts/ci/classify.sh`: prints the classes for a diff.
- `scripts/ci/merge-queue.sh PR`: merges a green PR without a re-run when main moved only outside the PR's classes, or updates the branch so CI runs again when it moved inside them. Turn off "require branches to be up to date" in branch protection; this script is the queue.
- `.github/workflows/ci.yml`: a classify job, one job per class that runs only when its class changed, the spec, setup and line-endings checks, a status page check on every run, a single summary job named `CI passed` that waits for whichever class jobs ran and reports once, the full suite on every push to main, and an issue labeled `ci-red` when that full run fails. No path filters on the workflow, so every update to a PR starts a run.
- `scripts/labels.sh`: creates the seven `state:` labels plus `task`, `ci-red` and `audit`.
- `scripts/board.sh OWNER OWNER/REPO`: creates the labels, the project board and its State field, and links the repository.
- `scripts/state.sh PROJECT OWNER ISSUE "Ready"`: sets the State field on the board for one issue, so the coordinator can do it right after filing.
- `.github/workflows/audit.yml`: nightly, comments on the issue labeled `audit` only when an open issue has no State label, a merged PR left its issue open and still ready, or a red-main issue is still open. Says nothing when clean.

## What the plugin does not do

The skill names four things the plugin leaves to the project, because they depend on where it is hosted:

- **The work folder outside the repo** with a research register and an off-site backup. It is outside the repo by design, so no template can create it. Make it by hand and name its path in CLAUDE.md.
- **Sharding the slow suite.** The app job has a comment showing where the matrix goes and the two common shard flags. The split itself depends on the runner.
- **A fallback runner** when self-hosted ones are offline. The full job has a comment on runner groups. Setting one up is a hosting decision.
- **A watcher on long-running work** that re-arms until it ends. The merge queue script runs once and exits. Run it from a scheduled workflow or a loop in the coordinator's session; the plugin does not start one for you.

Two rules in the skill have no mechanical check anywhere: "report what was not done and which commands were refused" and "stop every shell when done." CLAUDE.md says so, and a reviewer looks for them.

## Branch protection on main

Branch protection is set by hand in the repository's settings, under Branches. GitHub asks the owner to confirm their access before it saves the rule. Set it like this:

- **Require status checks to pass**, and require exactly one check: `CI passed`. Never add the per-class jobs. They are skipped on purpose when a change does not touch their class, and a required check that never reports blocks the merge forever. The `CI passed` job waits for whichever class jobs ran and reports once, so it is the only check main needs.
- **Leave "require branches to be up to date" off.** The merge queue merges a green pull request without a re-run when main changed only outside the pull request's classes. That rule depends on being allowed to merge a branch that is behind main. With the setting on, every merge to main would force every open pull request to update and run again, which is the queue that waits an hour per change this plugin exists to avoid.
- **Require a pull request before merging**, so the full run on main happens after a merge and never after a direct push.

## The project board

`scripts/board.sh` creates the board and a single-select field named State with seven values: `Ready`, `In progress`, `Waiting on owner`, `Waiting on a service`, `Parked`, `Dated`, `After launch`. The issue template's dropdown has the same seven, the `state-label` workflow turns the chosen one into the matching `state:` label (`state:ready`, `state:in-progress`, `state:waiting-on-owner`, `state:waiting-on-service`, `state:parked`, `state:dated`, `state:after-launch`), and the filing hook refuses an issue without one. Group the board view by State; that view is the status report, and nobody writes one.

The built-in workflows act on the board's own Status field, and the API cannot switch them on. After the script runs, open the board, choose the Workflows tab, and turn on these four by hand:

| Workflow | Setting |
|---|---|
| Auto-add to project | Repository: this one. Filter: `is:issue is:open` |
| Item closed | Set Status to `Done` |
| Pull request merged | Set Status to `Done` |
| Auto-add sub-issues to project | On, no settings |

Leave Auto-archive items off until the board is busy. There is no built-in workflow for State itself: the coordinator sets it at filing with `scripts/state.sh`, and the nightly audit catches the issues where that was missed.

## Tests

One command runs every test:

```bash
sh tests/run.sh
```

Each test feeds strings to one pure function and compares the output. A sample run:

```text
# delete_reason
ok    rm
ok    rm after cd
ok    git clean
ok    git status is fine
ok    a word containing rm is fine

# full_sweep_reason
ok    bare pytest
ok    pytest with a file is fine
ok    npm test
ok    npm test with a file is fine
ok    go test ./...
ok    go test one package is fine

# status check
ok    missing page fails
ok    fresh page passes
ok    stale page fails

# needs_rerun
ok    no overlap merges
ok    overlap reruns
ok    ci on main reruns

140 passed, 0 failed
```

## License

MIT. See `LICENSE`.
