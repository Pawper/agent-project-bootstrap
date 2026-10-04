# The merge queue

Merging should never take longer than the development did. One project merged seven app pull requests one at a time, each with its own full browser run, in ninety minutes. The same night, thirteen went into one integration branch with scoped tests per pull request and one full run, in twenty. The batch is the unit of merging; serial is the exception you name.

## When to batch

Any time there are more than two green pull requests waiting. Run the queue with `--batch` and the numbers in the order you want them merged, oldest or most foundational first:

```bash
sh scripts/ci/merge-queue.sh --batch 41 42 45 47
```

What happens, in order: an integration branch named for the day is cut from main; each pull request is merged with a merge commit, so the originals show as merged and close their issues; after each merge the type-check runs and then only the unit and component test files that pull request touched, one file at a time; a pull request that conflicts or goes red is dropped with one printed line and the branch goes back to the last good merge; the status page is rebuilt; one pull request is opened whose body carries a Closes line per pull request; the one full run happens; the batch merges with a merge commit; the dropped ones go through the serial queue afterward.

## When to go serial

By choice, for a change that must land alone: a migration, a change to the deploy, anything whose failure you want to see on its own. Say so:

```bash
sh scripts/ci/merge-queue.sh --serial 48
```

Two or fewer pull requests with no flag also run serially. More than two with no flag are refused, by the script and by the `require-batch-merge` hook, until you name the mode.

## Runners

Every open pull request starts its own CI run on every update. Once a pull request is in a batch, its own run is competing with the batch's run for the same runners and proving nothing the batch does not. The queue cancels a carried pull request's in-progress run for that reason. If you batch by hand, cancel them yourself.

## What the queue needs from the project

- A type-check command. It uses `npx tsc --noEmit` when a `tsconfig.json` is present; set `QUEUE_TYPECHECK_COMMAND` for anything else. With neither, the type-check step is skipped.
- A one-file test command. By default it runs `scripts/ci/run-test-file.mjs`, which drives the test runner's own API for one file so the hook that refuses sweeps is not in the way. Set `QUEUE_TEST_COMMAND` to another command that takes one file.
- Branch protection on main that requires only the `CI passed` check and leaves "require branches to be up to date" off.
