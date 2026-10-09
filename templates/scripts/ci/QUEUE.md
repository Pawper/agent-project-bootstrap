# The merge queue

Merging should never take longer than the development did. One project merged seven app pull requests one at a time, each with its own full browser run, in ninety minutes. The same night, thirteen went into one integration branch with scoped tests per pull request and one full run, in twenty. The batch is the unit of merging; serial is the exception you name.

## When to batch

Any time there are more than two green pull requests waiting. Run the queue with `--batch` and the numbers in the order you want them merged, oldest or most foundational first:

```bash
sh scripts/ci/merge-queue.sh --batch 41 42 45 47
```

What happens, in order: an integration branch named for the day is cut from main; each pull request is merged with a merge commit, so the originals show as merged and close their issues; after each merge the type-check runs and then only the unit and component test files that pull request touched, one file at a time; a pull request that conflicts or goes red is dropped with one printed line and the branch goes back to the last good merge; the status page is rebuilt; one pull request is opened whose body carries a Closes line per pull request; the one full run happens; the batch merges with a merge commit; the dropped ones go through the serial queue afterward.

## Drain: the queue that keeps going

Most of the time, nobody should pick the numbers. `--drain` reads every open pull request in one call, merges the green ones (as a batch when more than two), waits while others are still running CI, and goes round again until nothing is left, nothing new turned green, six rounds have passed, or ninety minutes have:

```bash
sh scripts/ci/merge-queue.sh --drain
```

That is the command for "merge what is ready", so no agent writes its own loop. To keep it going through a working session, run it on a timer: `/loop 20m sh scripts/ci/merge-queue.sh --drain`. A pull request a round could not merge is not tried again in that drain; its line says why. A red pull request gets one retry of its failed jobs. When the drain ends, every pull request that conflicts with main or failed twice is listed under "Needs attention" and the drain exits non-zero, so an agent running it on a timer is woken by the failure instead of reading past a log line.

## Inside the API budget

GitHub allows 5,000 API calls an hour for the account, shared by every tool and every agent. One evening with ten pull requests open, several waits running at once and `gh run watch` polling every few seconds spent it by midnight; from then every wait failed with a 403 that the queue reported as "not green yet", and nothing could land for an hour. The queue now paces itself:

- Every wait polls every thirty seconds, never faster, and the drain's rounds wait two minutes.
- Before each round and each wait it reads the budget (that call is free) and, when fewer than `QUEUE_RATE_FLOOR` calls are left (default 500), sleeps until the window resets and says so in one line.
- A 403 for the rate limit is named: "GitHub API rate limit reached; it resets at HH:MM UTC", and the queue stops.
- One queue at a time. A drain or a batch takes `.scratch/queue/lock`; a second one is refused with a line naming the first. A lock whose process is gone is taken over.
- The session brief shows the remaining budget when it is low.

Never write a watch loop around the queue, and never run `gh run watch` with its default interval; run `--drain` and let it pace itself. If you must watch one run by hand, `gh run watch ID -i 30`.

## Only through the queue

A direct `gh pr merge` is refused by the plugin's merge hook in any project that has this script, with one line pointing here. The queue is what checks the folder, waits for a quiet main, batches, cleans up the worktree and records flaky tests; a merge that skips it skips all of that.

## A change that needs a migration run

A pull request that adds a migration merges only after the migration has run. The queue reads the manual on the pull request's own branch, and refuses while the migration's line still says "Not yet run" or no line mentions it. Run it, change the line to "Done" with the date on that branch, and queue it again. Migrations are the `migration` kind in `.claude/numbering.txt`; the manual is `SETUP.md` or the `manual` line in `setup-paths.txt`.

## When to go serial

By choice, for a change that must land alone: a migration, a change to the deploy, anything whose failure you want to see on its own. Say so:

```bash
sh scripts/ci/merge-queue.sh --serial 48
```

Two or fewer pull requests with no flag also run serially. More than two with no flag are refused, by the script and by the `require-batch-merge` hook, until you name the mode.

## Runners

Every open pull request starts its own CI run on every update. Once a pull request is in a batch, its own run is competing with the batch's run for the same runners and proving nothing the batch does not. The queue cancels a carried pull request's in-progress run for that reason. If you batch by hand, cancel them yourself.

## What the queue says while it waits

The queue reads the run it waits on and says plainly what is happening, so a stuck run is a line of output and not half an hour of diagnosis.

- **"GitHub Actions is down, not your code."** When a job's annotation says it was not acquired by a hosted runner, or a job has sat queued for more than five minutes while runners of ours were idle. The line adds GitHub's own status for Actions when it is not operational. If the project has an outage switch, set `QUEUE_OUTAGE_ON` and `QUEUE_OUTAGE_OFF` to the commands that flip it, for example `gh variable set CI_OUTAGE --body 1` and `gh variable delete CI_OUTAGE`; the queue flips it on for that run and off again when the run goes green.
- **"CI failed: lint, test."** The failing jobs by name, and the failing tests read from the run's log.
- **"The run you are waiting on was canceled; re-running it."** Instead of silence.
- **"Holding the merge: a run on main is in flight."** The queue never merges while a run on main is in progress, so a proof run on main is never canceled by a merge. It holds for up to twenty minutes, then says so and merges.

The wait is bounded by `QUEUE_WAIT_MINUTES`, default sixty; past it the queue says so and stops, and a later run picks up.

## An unreliable test is a bug, not weather

The queue keeps a record under `.scratch/queue/flaky.tsv`: each test that failed on a pull request and then passed on a retry, by name, with the pull request and the day. A test that flakes twice gets an issue filed, labeled bug and ready, naming the pull requests it cost, and the queue says so. After that it is not re-run again; it is fixed or quarantined under its own issue. The record is local to the machine that runs the queue, which is the one that sees every result.

## Before a self-hosted runner's first run

Run the doctor on the machine: `sh scripts/ci/runner-doctor.sh`. It checks the four things that cost a real project four tries: which bash a step would get (Windows puts WSL's first), whether Git, Node and gh are on the machine PATH the runner service sees, PowerShell's execution policy, and whether the runner is online. Then run the `Runner check` workflow from the Actions tab once; it is the job-level shell default and the PowerShell step, written the way that works.

## What the queue needs from the project

- A type-check command. It uses `npx tsc --noEmit` when any `tsconfig.json` is checked in, run once in each package a change touches (the nearest folder above each changed file with a `tsconfig.json`), so an app in `web/` is checked from `web/`. Set `QUEUE_TYPECHECK_COMMAND` for the project's own command, which runs once from the root. With neither, the type-check step is skipped.
- A one-file test command. By default it runs `scripts/ci/run-test-file.mjs`, which drives the test runner's own API for one file so the hook that refuses sweeps is not in the way. It runs the file from its own package, the nearest folder above it with a `package.json`, where its `node_modules` and runner config live. Set `QUEUE_TEST_COMMAND` to another command that takes one file. A runner that cannot start is not a red test: the batch stops and prints the runner's error instead of dropping every pull request.
- Branch protection on main that requires only the `CI passed` check and leaves "require branches to be up to date" off.
