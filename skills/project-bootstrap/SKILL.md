---
name: project-bootstrap
description: Stand up a new project so many agents can work in it at once without colliding. Use at the start of a project, before the first feature agent runs, or when an existing project shows the symptoms (docs that grow by appending, merge conflicts on shared files, a merge queue that waits on full test runs, a project board nobody feeds).
---

# Project bootstrap

The lesson this comes from: rules written for one agent become pathologies when thirty follow them at once, and
the codebase is the one surface every agent must write to, so anything that lives there is something they all
collide on. Decide the homes and the enforcement first, then let agents build.

## 1. Homes: one place for each kind of thing

Write these into the project's CLAUDE.md (and AGENTS.md as a copy for other tools). Nothing goes anywhere else.

| Kind | Home | Never |
|---|---|---|
| Work, decisions, priorities | GitHub issues, one per task, filed before an agent starts; the PR closes it; decisions are comments on it | status files, TODO lists in the repo |
| Status at a glance | The project board, fed by GitHub's own automation (issue opened adds a card, a linked PR moves it to In progress, merge moves it to Done) and a State label set at filing | a hand-kept status page |
| Orientation for an agent starting cold | One short status page in the repo (a table with one row per feature and its state, a services summary, a not-done list), generated from one small stub per feature and checked in CI | per-day or per-item diaries |
| Data | The database, edited through the app's admin; seed files in the repo only as reviewable input to an importer, one file per unit so parallel changes touch different files | hand-written copies of data in prose |
| Research and findings | A work folder beside the source material, outside the repo, backed up off-site | the docs folder |
| Coordination state (what merged when, what was uploaded) | git history, CI, the storage bucket | written down by hand |
| The manual | One setup document: configuration, keys by name, migrations run | anything that changes per feature |
| Design | A spec folder per feature, written with the spec kit before building | design notes in issues only |
| Credit for borrowed code or content | One short notice file, like any license notice | per-item narrative |

## 2. Rules for every agent

- File the issue first. Work in an isolated worktree. Never force-push. Never delete; move aside.
- A PR carries its feature's spec stub and a setup line when a setup step changes, and nothing appended to a shared page.
- Tests prove the change and run per file; the full suite is the gate on main, not on the PR.
- Everything a person sees is calm and plain, never a developer note (no issue numbers, fields, migrations).
- Report what was not done and why, not only what was. Say which commands were refused.
- No wait loops; bounded commands; stop every shell when done.

## 3. Enforcement: for every rule, what checks it

An instruction decays under load. For each rule, decide which of these makes it true, and set it up in the
first hour:

- **A hook that blocks the dangerous command** (delete, force-push, full test sweep, a direct write to a shared
  page) rather than asking the agent to avoid it.
- **A CI check that fails on drift**: the data shape, the generated status page, the catalog-wide rules, the
  line endings.
- **A required field at filing**, where the agent already has the information: an issue template with a State
  label (waiting on owner, waiting on a service, parked, dated, ready), and a hook that refuses an issue without one.
- **A scheduled audit that speaks only when something is wrong**: open issues with no state, PRs merged with a
  stale label, a red main run; one comment on a tracking issue, nothing when clean.
- **A watcher on anything long-running** (a merge queue, an upload, a build), re-armed until it ends.

If a rule has none of these, either give it one or accept that it will not hold.

## 4. CI and merging from day one

- Classify a PR by the files it touches and run only what those touch; shard the slow suite across runners.
- The full run is the gate on main after every merge; a red main opens an issue automatically.
- The merge queue merges a green PR without a re-run when main changed only outside the PR's classes.
- No path filters that can skip a run on an update (a merge from main that touches only docs must still start one, or the queue waits forever).
- A fallback runner when the self-hosted ones are offline.

## 6. The project board, exactly

Create one GitHub project for the repository and set it up so nothing has to be updated by hand:

- **A State field**, single select, with these values: Ready, In progress, Waiting on owner, Waiting on a service, Parked, Dated, After launch. Create it with `gh project field-create <number> --owner <owner> --name State --data-type SINGLE_SELECT --single-select-options "Ready,In progress,Waiting on owner,Waiting on a service,Parked,Dated,After launch"`. Matching labels (`state: ready` and so on) on the repository, for the filing hook.
- **Built-in workflows**, in the project's Workflows tab (the API cannot switch them on, so this is a one-time click each): Auto-add to project with the filter `is:issue is:open` on the repository; Item closed, set Status to Done; Pull request merged, set Status to Done; Auto-add sub-issues to project. Leave Auto-archive off until the board is busy.
- **At filing**, the coordinator sets State on the new issue (`gh project item-edit` with the field and option ids from `gh project field-list`); the filing hook refuses an issue without a state label.
- **The board view**: group by State. That view is the status report; nobody writes one.
- **A nightly audit** (a scheduled workflow) lists open issues with no State or with a merged PR and a stale State, as one comment on a tracking issue, and says nothing when clean.
## 5. Outputs of this skill

Create, in order:
1. The repository with CLAUDE.md and AGENTS.md from section 1 and 2, short, pointing at the hooks and checks.
2. The issue template with the State label; the project board set up exactly as section 6 says; the labels.
3. The hooks (user or project settings): block delete, force-push, full sweeps, direct writes to generated pages, issue creation without a state label.
4. The CI skeleton from section 4, with the classifier and the status-page check.
5. The setup document, the notice file, the one-screen status page and its build and check scripts.
6. The work folder outside the repo, with a register for research and an off-site backup scheduled.
7. The spec kit constitution, then the first spec.

Then the first feature agent runs.
