---
name: project-bootstrap
description: Stand up a new project so many agents can work in it at once without colliding. Use at the start of a project, before the first feature agent runs, or when an existing project shows the symptoms (docs that grow by appending, merge conflicts on shared files, a merge queue that waits on full test runs, a project board nobody feeds).
---

# Project bootstrap

The lesson this comes from: rules written for one agent become pathologies when thirty follow them at once, and
the codebase is the one surface every agent must write to, so anything that lives there is something they all
collide on. Decide the homes and the enforcement first, then let agents build.

## Before anything: a short survey

Do not copy a file until these are answered. Look in the repository first (the remote URL, a `.gitlab-ci.yml`
or `.github/`, the package manifest, an existing `specs/` or `docs/` folder, a `CLAUDE.md`), state what you
found, and ask only what you could not tell. Ask in one message, as a short list, with your inference as the
default for each. In Claude Code use the question tool so the person can pick rather than type.

| Question | Why it matters | Changes |
|---|---|---|
| New project, or an existing one showing the symptoms? | An existing project needs the hooks and checks first and the moves to new homes second, one at a time | The order of the outputs; what is moved aside rather than created |
| Where do issues live: GitHub, GitLab, Jira, Linear, other? | Every home in section 1 points at the tracker | The issue template, the board script, the state script, the audit, the filing hook's label |
| Where does CI run: Actions, GitLab CI, Buildkite, other? | Section 4 is a set of jobs; the file that holds them differs | Which workflow files are copied or translated |
| Which agent runtimes will work here: Claude Code only, or others too? | Hooks are per runtime; a rule with no hook needs a CI check instead | Whether AGENTS.md is a copy or the primary; which rules get a weaker check |
| What is the one-file test command? | The sweep hook needs to know what a targeted run looks like; CLAUDE.md states it | The `TEST_COMMAND` placeholder; the per-class jobs |
| Which pages are generated? | The generated-page hook refuses edits to them | `.claude/generated-pages.txt` |
| Spec tool: by hand, GitHub's spec-kit, something else, none yet? | Step 7 and the spec check assume a folder per feature; the tool that fills it is the person's choice | Whether to run a generator inside `specs/<feature>/` or copy the skeleton |
| Self-hosted runners? | Section 4 wants a fallback when they are offline | Whether the runner-group comment in the full job becomes real |
| Where will the work folder live, and where is it backed up? | Step 6 is outside the repo and nothing can create it for you | The path named in CLAUDE.md |
| Is there a manual already, and where? | The setup check asks for a line in the manual whenever a setup file changes; it must point at the one the project keeps | The `manual PATH` line in `scripts/ci/setup-paths.txt`; the manual row in the homes table |
| Which routine tasks and limits does this project really have? | The console's FAQ must answer this project's questions, not the sample's | The `faq.required` ids in `console/services.json` |

Record the answers at the top of CLAUDE.md under a heading "Stack", three or four lines, so the next agent does not
ask again. If the answers match the preferred stack, say so in one line and go on. If they do not, use section 0.

## 0. The stack this was designed for, and adapting to another

This skill and its plugin were built for GitHub (issues, a project board, Actions, the `gh` CLI), Claude Code
hooks, and a spec folder per feature in plain Markdown. Be honest about that: say it once when the project uses
something else, then adapt. Every home and every rule below is about a kind of place, not a product. When the
project does not use the preferred tool, propose the nearest equivalent and keep the rule:

| Preferred | If the project uses | Propose |
|---|---|---|
| GitHub issues, one per task | GitLab, Jira, Linear, a plain tracker | Their issue with a required State field or label; the PR or MR still closes it |
| GitHub project board with a State field | GitLab boards, Jira board, Linear views | A board grouped by State fed by the tracker's own automation, never a hand-kept page |
| GitHub Actions | GitLab CI, Buildkite, Jenkins, CircleCI | The same jobs: classify, per-class, one summary check, full run on main, red run opens an issue |
| `gh` in scripts | `glab`, a REST call, the tracker's CLI | The same scripts with the calls swapped; keep the pure parts, which are tool-free |
| Claude Code hooks | Another agent runtime | That runtime's pre-command hook if it has one; otherwise a CI check or a git hook, and say the rule is weaker |
| Spec folder per feature, written by hand or with GitHub's spec-kit | Any spec tool, or none | A folder per feature in the repo with a constitution and a spec file; the CI check holds either way |

What never changes: one home per kind of thing, nothing appended to a shared page, every rule has something that
enforces it, and the full suite gates main rather than the PR.

## 1. Homes: one place for each kind of thing

Write these into the project's CLAUDE.md (and AGENTS.md as a copy for other tools). Nothing goes anywhere else.

| Kind | Home | Never |
|---|---|---|
| Work, decisions, priorities | GitHub issues, one per task, filed before an agent starts; the PR closes it; decisions are comments on it | status files, TODO lists in the repo |
| Status at a glance | The project board, with a State field set at filing by the coordinator and moved to Done by GitHub's own automation when the PR merges or the issue closes | a hand-kept status page |
| Orientation for an agent starting cold | One short status page in the repo (a table with one row per feature and its state, a services summary, a not-done list), generated from one small stub per feature and checked in CI | per-day or per-item diaries |
| Data | The database, edited through the app's admin; seed files in the repo only as reviewable input to an importer, one file per unit so parallel changes touch different files | hand-written copies of data in prose |
| Research and findings | A work folder beside the source material, outside the repo, backed up off-site | the docs folder |
| Coordination state (what merged when, what was uploaded) | git history, CI, the storage bucket | written down by hand |
| The manual | One setup document: configuration, keys by name, migrations run | anything that changes per feature |
| Design | A spec folder per feature, with a constitution written once and a spec file per feature, written before building (by hand, or with GitHub's spec-kit if the project wants a generator) | design notes in issues only |
| Credit for borrowed code or content | One short notice file, like any license notice | per-item narrative |

## 2. Rules for every agent

- File the issue first, with a State. Work in an isolated worktree. Never force-push. Never delete; move aside.
- A PR carries its feature's spec change and a setup line when a setup step changes, and nothing appended to a shared page.
- Tests prove the change and run per file; the full suite is the gate on main, not on the PR.
- Everything a person sees is calm and plain, never a developer note (no issue numbers, fields, migrations).
- Report what was not done and why, not only what was. Say which commands were refused.
- No wait loops; bounded commands; stop every shell when done.
- Dispatch an agent with a model that fits its task: a light model for a lookup, a middle one for routine work, a heavy one only for hard work.

## 3. Enforcement: for every rule, what checks it

An instruction decays under load. For each rule, decide which of these makes it true, and set it up in the
first hour:

- **A hook that blocks the dangerous command** (delete, force-push, full test sweep, a direct write to a shared
  page, an issue without a State, an agent dispatched without a fitting model) rather than asking the agent to avoid it.
- **A CI check that fails on drift**: the generated status page, a source change without its spec, a setup
  change without its setup line, line endings, and, when the project has them, the data shape and the
  catalog-wide rules.
- **A required field at filing**, where the agent already has the information: an issue template with a State
  field, matching labels, and a hook that refuses an issue without one.
- **A scheduled audit that speaks only when something is wrong**: open issues with no State, issues left stale by
  a merged PR, a red main run; one comment on a tracking issue, nothing when clean.
- **A watcher on anything long-running** (a merge queue, an upload, a build), re-armed until it ends.

If a rule has none of these, either give it one or accept that it will not hold. Two rules in section 2 have no
mechanical check: "report what was not done" and "stop every shell." Say so in CLAUDE.md and review for them.

## 4. CI and merging from day one

- Classify a PR by the files it touches and run only what those touch; shard the slow suite across runners.
- One summary check, `CI passed`, waits for whichever class jobs ran and reports once. Branch protection on main
  requires exactly that check and never a per-class job, since those are skipped on purpose.
- The full run is the gate on main after every merge; a red main opens an issue automatically.
- The merge queue merges a green PR without a re-run when main changed only outside the PR's classes. This
  depends on "require branches to be up to date" staying off in branch protection.
- No path filters that can skip a run on an update (a merge from main that touches only docs must still start one, or the queue waits forever).
- A fallback runner when the self-hosted ones are offline.

## 5. The project board, exactly

Create one GitHub project for the repository and set it up so nothing has to be updated by hand:

- **A State field**, single select, with these seven values: Ready, In progress, Waiting on owner, Waiting on a service, Parked, Dated, After launch. Create it with `gh project field-create <number> --owner <owner> --name State --data-type SINGLE_SELECT --single-select-options "Ready,In progress,Waiting on owner,Waiting on a service,Parked,Dated,After launch"`. Matching labels on the repository, `state:ready` through `state:after-launch`, for the filing hook.
- **Built-in workflows**, in the project's Workflows tab (the API cannot switch them on, so this is a one-time click each): Auto-add to project with the filter `is:issue is:open` on the repository; Item closed, set Status to Done; Pull request merged, set Status to Done; Auto-add sub-issues to project. Leave Auto-archive off until the board is busy. These act on the board's own Status field; nothing built in moves State.
- **At filing**, the coordinator sets State on the new issue (`gh project item-edit` with the field and option ids from `gh project field-list`); the filing hook refuses an issue without a state label.
- **The board view**: group by State. That view is the status report; nobody writes one.
- **A nightly audit** (a scheduled workflow) lists open issues with no State, issues still open and Ready after their PR merged, and an open red-main issue, as one comment on a tracking issue, and says nothing when clean.

## 6. Outputs of this skill

Create, in order:
1. The repository with CLAUDE.md and AGENTS.md from sections 1 and 2, short, pointing at the hooks and checks.
2. The issue template with the State field; the project board set up exactly as section 5 says; the labels.
3. The hooks, which the plugin provides: block delete, force-push, full sweeps, direct writes to generated pages, issue creation without a state label, agent dispatch without a fitting model.
4. The CI skeleton from section 4: the classifier, the per-class jobs, the `CI passed` summary, the status-page, spec, setup-line and line-endings checks, the full run on main, the merge queue, the nightly audit. Then branch protection by hand.
5. The setup document, the notice file, the one-screen status page and its build and check scripts.
6. The work folder outside the repo, with a register for research and an off-site backup scheduled.
7. The constitution, then the first spec.
8. The owner console: `console/services.json` listing every outside system, the settings each depends on with a plain label, the links, the launch to-do with its flags, and the FAQ; served locally with `npx agent-project-bootstrap console`, and mounted online behind the owner sign-in when wanted. Its check fails when a name in the example env file has no card.

Then the first feature agent runs.

## On an existing project

A repository with history, open pull requests and agents already at work gets the same pieces in a different
order, one pull request per step, so nothing lands all at once and nothing working is replaced by a skeleton.

1. **Survey first**, as above. Name the shared pages that grow by appending and the hand-kept status page; they
   are the symptoms, and they become inputs below.
2. **Hooks on, and the generated-pages list filled in** with the repository's real shared pages, so the next
   append is refused the same day. Tell the team in one message what the six hooks refuse and what to do instead.
3. **Labels and the audit.** The first night's comment will list every open issue with no State. That is the
   backlog, not a failure; work it down over the week.
4. **The status page, mined from what exists.** Write one stub per existing feature from the old status page,
   build STATUS.md, then move the old page aside (`git mv`, never delete) and add it to the generated-pages list
   if anything still points at it.
5. **CI, in this order:** the summary job and the setup check first, since they fail nothing that passes today;
   then the spec check, which is incremental by design (each feature gets its folder when it is next touched);
   then line endings, which is one deliberate normalizing commit made when no pull requests are open, because
   it conflicts with every branch that was cut before it.
6. **The board.** If one exists, give its number to the board script instead of letting it create a second.
7. **The console**, from the example env file the project already has; the check names every setting that
   still has no card, which is the list of systems to describe.

Two files the project may already have deserve a word. **The manual:** keep the one that exists, name it on a
`manual PATH` line in `scripts/ci/setup-paths.txt`, and do not create `SETUP.md` beside it. **The console's
questions:** the sample lists the questions of a project with uploads, claims and an importer; a project with
other flows writes its own ids under `faq.required` and answers those.

Never overwrite. For every template whose file already exists, write the skeleton beside it as
`NAME.bootstrap.md` (or `.bootstrap.yml`, and so on) and leave the merge to a person. The templates are the
shape; the existing file is the truth until someone says otherwise.

## Where the pieces are

When this skill runs from the plugin, the hooks in step 3 are already active and the files for the other steps
are ready to copy from `${CLAUDE_PLUGIN_ROOT}/templates/`:

- Step 1: `CLAUDE.md`, `AGENTS.md`, `.claude/generated-pages.txt`
- Step 2: `.github/ISSUE_TEMPLATE/`, `.github/workflows/state-label.yml`, `scripts/labels.sh`, `scripts/board.sh`, `scripts/state.sh`
- Step 4: `.github/workflows/ci.yml`, `scripts/ci/` (classes, classifier, merge queue, spec, setup and line-endings checks), `.github/workflows/audit.yml`
- Step 5: `SETUP.md`, `NOTICE.md`, `status/` and the `STATUS.md` it builds
- Step 6: nothing in the plugin; it lives outside the repo, so create it by hand and name its path in CLAUDE.md
- Step 7: `specs/constitution.md` and `specs/FEATURE/spec.md`, checked by `scripts/ci/spec-check.sh`
- Step 8: `console/services.json` and `.env.example`; the page itself comes from the plugin's `console/` and needs no copy

Copy them into the new repository, replace every CAPITALIZED placeholder, run `sh scripts/board.sh OWNER OWNER/REPO`,
switch on the board's built-in workflows and set branch protection by hand, and build the status page once with
`sh status/build.sh`. When the project is not on GitHub, say so, use section 0, and keep the pure parts of the scripts.
