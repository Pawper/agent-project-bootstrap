# Self-hosted runners

A runner that fails quietly costs more than a slow one: every check sits queued or fails for no reason anyone can see. These are the rules that keep that from happening.

## Install each runner as a service

A runner started by hand in a terminal stops when the terminal closes, the user logs out, or the machine restarts, and nothing says so. Install it as a Windows service instead. `scripts/ci/add-runner.ps1 -Name NAME` does the whole thing: registration token, download, configuration with the labels the workflows expect, service install and start. A runner installed by hand can be moved over with `config.cmd remove`, then the script.

The service runs as NETWORK SERVICE, which sees only the machine PATH, not your user PATH. Git, Node and gh must be on the machine PATH. The doctor checks that.

## Run two

One runner is a queue of one: a slow job makes every other job wait, and when it goes offline everything stops. Run at least two, on the same machine or on two. Each is one run of `add-runner.ps1` with a different name.

## Keep the runner's environment clean

A runner picks up whatever environment it starts with, and a setting meant for one tool can break another. One project had every Android build fail because the runner had picked up a machine-wide setting meant for something else. Keep tool settings out of the machine environment and out of the runner's `.env` file; set what a job needs in the workflow's `env:` block, where it is visible and scoped to that job. The `Runner check` workflow prints what a job actually sees.

## Before the first run, and after any change to the machine

1. `sh scripts/ci/runner-doctor.sh` on the machine: which bash a step gets, whether Git, Node and gh are on the machine PATH, PowerShell's execution policy, and whether each runner is online.
2. The `Runner check` workflow from the Actions tab: Git's bash named by path, a PowerShell step, and the tools the job sees.

## When it goes wrong anyway

`Runner watch` runs hourly on a hosted runner, so it works when ours are down. It comments on the issue labeled `audit` when a runner is offline, when fewer than two are online, or when any run has sat queued for more than ten minutes, and says nothing otherwise. The merge queue also says "GitHub Actions is down, not your code" when the hosted side is the problem, so the two are never confused.
