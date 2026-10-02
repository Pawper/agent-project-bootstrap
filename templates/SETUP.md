# Setup

The one manual for this project. It holds what a person or an agent needs to run the project from a clean machine: configuration, the names of keys, and the migrations that have been run. It never holds anything that changes per feature; that belongs in the feature's spec and its status stub.

When a PR changes a setup step, it changes the line here in the same PR.

## Requirements

- RUNTIME and version
- DATABASE and version
- Any tool a developer must install by hand

## Configuration

Every value comes from the environment. List the name, what it is for, and where the value lives. Never the value itself.

| Name | What it is for | Where it lives |
|---|---|---|
| `DATABASE_URL` | The main database | The team password manager, entry PROJECT_NAME |
| `SERVICE_API_KEY` | Access to SERVICE | The team password manager, entry PROJECT_NAME |

## First run

1. Clone the repository and install the dependencies with `INSTALL_COMMAND`.
2. Copy `.env.example` to `.env` and fill in the names above.
3. Run the migrations with `MIGRATE_COMMAND`.
4. Start the app with `START_COMMAND`.

## Migrations run

One line per migration, in order, with the date it ran in production. The newest line is at the bottom.

| Migration | Ran in production |
|---|---|
| `0001_initial` | YYYY-MM-DD |

## Services

| Service | What it does for us | Status page |
|---|---|---|
| SERVICE | One line | URL |
