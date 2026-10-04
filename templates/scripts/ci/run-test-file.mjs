#!/usr/bin/env node
// Run one test file through the test runner's own API, so the queue can
// prove a merged PR without a sweep. A hook refuses the bare sweep command
// on purpose; this is the targeted run it asks for.
//
// Usage: node scripts/ci/run-test-file.mjs path/to/one.test.ts
// Exit 0 when the file passes, 1 when it fails, 2 when it cannot run.

const file = process.argv[2];
if (!file) {
  process.stderr.write('Give one test file to run.\n');
  process.exit(2);
}

let startVitest;
try {
  ({ startVitest } = await import('vitest/node'));
} catch (e) {
  process.stderr.write('The test runner is not installed in this project; install it or set QUEUE_TEST_COMMAND to the project\'s one-file test command.\n');
  process.exit(2);
}

const ctx = await startVitest('test', [file], { run: true, watch: false, reporters: ['dot'] });
if (!ctx) {
  process.stderr.write(`The runner did not start for ${file}.\n`);
  process.exit(2);
}
await ctx.close();
const failed = typeof ctx.state?.getCountOfFailedTests === 'function'
  ? ctx.state.getCountOfFailedTests()
  : (process.exitCode || 0);
process.exit(failed > 0 ? 1 : 0);
