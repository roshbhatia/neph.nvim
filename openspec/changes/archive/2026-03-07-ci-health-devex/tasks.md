## 1. Pin nix flake

- [x] 1.1 Run `nix flake update` to generate `flake.lock`, commit it
- [x] 1.2 Remove all `--no-write-lock-file` flags from `.github/workflows/ci.yml`

## 2. Wire up pi tests

- [x] 2.1 Add `"test": "vitest"` script and vitest devDependency to `tools/pi/package.json`
- [x] 2.2 Add `test:pi` task to `tools/Taskfile.yml` and add it to `test` deps
- [x] 2.3 Run pi tests locally to verify they pass (fix if needed)

## 3. Consolidate CI

- [x] 3.1 Rewrite `.github/workflows/ci.yml` to a single job: one `nix develop` invocation running npm ci, lint, test, and e2e sequentially
- [x] 3.2 Add `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }` to the workflow

## 4. Agent contract test fixtures

- [x] 4.1 Create `tools/neph-cli/tests/fixtures/` with JSON fixtures: `claude-write.json`, `claude-edit.json`, `copilot-edit.json`, `gemini-write.json`, `gemini-edit.json`, `cursor-post.json`
- [x] 4.2 Write `tools/neph-cli/tests/gate.contract.test.ts` that loads each fixture and asserts the correct parser returns a valid `GatePayload`

## 5. Local checks and hooks

- [x] 5.1 Add `tsc --noEmit` for neph-cli to `task check` in root `Taskfile.yml`
- [x] 5.2 Create `.githooks/pre-push` script that runs `task check`
- [x] 5.3 Add CI badge to README.md

## 6. Verify

- [x] 6.1 Push and confirm CI passes as a single consolidated job
