## 1. E2E Test Harness

- [ ] 1.1 Create `tests/e2e/harness.lua` — minimal test framework with `describe`, `it`, `assert_eq`, `wait_for` (vim.wait wrapper), pass/fail tracking, and exit code reporting
- [ ] 1.2 Create `tests/e2e/run.lua` — entry point that loads harness, discovers and runs test files, reports results, exits with appropriate code
- [ ] 1.3 Create `tests/e2e/smoke_test.lua` — verify `require("neph").setup()` succeeds, `agents.get_all()` returns a table, no errors thrown

## 2. Tool Installation Tests

- [ ] 2.1 Create `tests/e2e/tools_test.lua` — verify `tools.install()` runs without error, check neph symlink exists at `~/.local/bin/neph`, check claude settings merge creates hooks key
- [ ] 2.2 Add dist freshness assertion — verify `tools/pi/dist/pi.js` exists and mtime >= `tools/pi/pi.ts` mtime (catches stale bundle bug)

## 3. Agent Launch Tests

- [ ] 3.1 Create `tests/e2e/agent_launch.lua` — shell script wrapper that runs a per-agent nvim --headless invocation for each installed agent, collects exit codes
- [ ] 3.2 Create `tests/e2e/launch_one.lua` — Lua script that receives agent name via env var, opens session, waits for terminal buffer, verifies vim.g state, closes session, exits
- [ ] 3.3 Add timeout handling — if agent launch or close exceeds 10s, kill nvim and report failure

## 4. Taskfile Integration

- [ ] 4.1 Add `test:e2e` task to root Taskfile.yml that runs `nvim --headless -l tests/e2e/run.lua` for smoke/tools tests, then `tests/e2e/agent_launch.lua` for per-agent tests
- [ ] 4.2 Add `test:e2e` as a dependency of the `test` task (runs after unit tests)

## 5. CI Pipeline Integration

- [ ] 5.1 Update `.fluentci/ci.ts` — add agent install step (npm install -g @mariozechner/pi-coding-agent, claude is already available via npm)
- [ ] 5.2 Add e2e test stage to `.fluentci/ci.ts` that runs `task test:e2e` after lint and unit tests
- [ ] 5.3 Ensure neph CLI is built and on PATH before e2e tests (tools:build must run first, neph symlink must exist)

## 6. Validation

- [ ] 6.1 Run e2e tests locally — verify smoke and tools tests pass, verify agent launch tests skip gracefully for missing agents
- [ ] 6.2 Run full CI pipeline locally via `task dagger` or `task ci` — verify e2e stage passes
