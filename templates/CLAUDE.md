# PROJECT_NAME

One line on what this project is. Replace every CAPITALIZED placeholder.

Many agents work here at once. Each kind of thing has one home, every rule has something that enforces it, and nothing is appended to a shared page.

## Stack

- Issues and board: GitHub. CI: GitHub Actions. Agent runtime: Claude Code.
- One-file test command: `TEST_COMMAND path/to/file`. Generated pages: `STATUS.md`.
- Specs: by hand in `specs/<feature>/`. Work folder: WORK_FOLDER, backed up to BACKUP_LOCATION.

## Homes

| Kind | Home | Never |
|---|---|---|
| Work, decisions, priorities | GitHub issues, one per task, filed before an agent starts; the PR closes it; decisions are comments on it | status files, TODO lists in the repo |
| Status at a glance | The project board, fed by GitHub's own automation and the State label set at filing | a hand-kept status page |
| Orientation for an agent starting cold | `STATUS.md`, generated from one stub per feature in `status/stubs/` and checked in CI | per-day or per-item diaries |
| Data | The database, through the app's admin; seed files in `SEED_DIR/` only as input to the importer, one file per unit | hand-written copies of data in prose |
| Research and findings | The work folder outside the repo at WORK_FOLDER, backed up off-site | the docs folder |
| Coordination state (what merged when, what was uploaded) | git history, CI, the storage bucket | written down by hand |
| The manual | `SETUP.md`: configuration, keys by name, migrations run | anything that changes per feature |
| Design | `specs/FEATURE/`, written before building | design notes in issues only |
| Credit for borrowed code or content | `NOTICE.md` | per-item narrative |

## Rules

- File the issue first, with a State label. Work in an isolated worktree. Never force-push. Never delete; move aside.
- A PR carries its feature's spec stub and a line in `SETUP.md` when a setup step changes, and nothing appended to a shared page.
- Tests prove the change and run per file. The full suite is the gate on main, not on the PR.
- Everything a person sees is calm and plain, never a developer note: no issue numbers, fields or migrations in user-facing text.
- Report what was not done and why, not only what was. Say which commands were refused.
- No wait loops; bounded commands; stop every shell when done.

## What enforces each rule

| Rule | Enforced by |
|---|---|
| Never delete | The `block-delete` hook refuses rm, del, Remove-Item and git clean |
| Never force-push | The `block-force-push` hook refuses any forced push |
| Tests per file | The `block-full-test-sweep` hook refuses a bare test command; CI runs the full suite on main |
| Nothing appended to a generated page | The `block-generated-page` hook refuses direct edits to the pages in `.claude/generated-pages.txt`; `sh status/check.sh` fails in CI when `STATUS.md` is stale |
| Every issue has a State | The issue template requires it; the `require-state-label` hook refuses `gh issue create` without `--label state:...`; the `state-label` workflow keeps the label in step with the field; `sh scripts/state.sh` sets it on the board |
| A red main is seen | The `full` CI job opens an issue labeled `ci-red` when it fails |
| No usage wasted on dispatch | The `require-agent-model` hook refuses an agent or workflow dispatch without a model that fits the task |
| Merging never outlasts the work | The `require-batch-merge` hook refuses more than two PRs through the queue without `--batch` or `--serial`; see `scripts/ci/QUEUE.md` |
| A setup change carries its line | The `setup-check` CI job fails a PR that changes a file in `scripts/ci/setup-paths.txt` without changing `SETUP.md` |
| A source change carries its spec | The `spec-check` CI job fails a PR that changes `src/` without a change in a `specs/<feature>/` folder |
| Line endings stay LF | `.gitattributes` forces it and the `line-endings` CI job fails on any CRLF file |
| Nothing drifts quietly | The nightly `audit` workflow comments on the issue labeled `audit` when an issue has no State, a merged PR left one stale, or a red-main issue is still open, and says nothing when clean |

Two rules have no mechanical check and are reviewed by hand: report what was not done and which commands were refused, and stop every shell when done.

## Not on GitHub?

These files were written for GitHub, Actions and `gh`. If this project uses something else, say so once, keep every rule, and swap the tool: the tracker's issue with a State field, its board grouped by State, its CI with the same jobs, its CLI in the scripts. The pure parts of every script are tool-free.

The hooks come from the `project-bootstrap` plugin. If a hook refuses a command, do what its message says; do not look for a way around it.

## Commands

- Build the status page: `sh status/build.sh`
- Check it is current: `sh status/check.sh`
- Run one test file: `TEST_COMMAND path/to/file`
- Classify a change: `sh scripts/ci/classify.sh`
- Open the owner console: `npx agent-project-bootstrap console`; check its config: `npx agent-project-bootstrap console --check`. Adding a service means adding an entry to `console/services.json`.
