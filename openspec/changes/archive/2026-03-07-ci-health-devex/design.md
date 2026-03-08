## Context

CI currently runs 3 parallel jobs (lint, test, e2e) that each independently: checkout, install nix, cache nix, and run `npm ci` 3 times. The nix flake is unpinned (`--no-write-lock-file`), pi tests exist but aren't wired up, and there's no local pre-push validation.

The total work is small (lint <5s, tests <10s, e2e <30s) so parallelizing across jobs wastes more time on setup overhead than it saves.

## Goals / Non-Goals

**Goals:**
- CI wall-clock time under 2 minutes for the common case
- Every test file in the repo is actually executed by CI
- Reproducible builds via pinned flake.lock
- Fast local feedback via `task check` and git hooks
- Contract tests catch agent JSON format regressions

**Non-Goals:**
- Matrix testing across multiple neovim versions (future work)
- Caching node_modules across CI runs (nix handles node, complicates caching)
- Adding pi type-checking (pi uses deno lint, not tsc; separate concern)

## Decisions

### 1. Single CI job instead of three parallel jobs

**Choice:** Merge lint, test, and e2e into one job with sequential steps inside a single `nix develop` invocation.

**Why:** Setup overhead (nix eval + npm ci x3) takes ~60s per job. The actual work takes <45s total. One job with one setup saves ~2 minutes.

**Alternative:** Keep parallel jobs but share a build artifact. Rejected because the total work is too small to benefit from parallelism, and artifact upload/download adds its own overhead.

### 2. Pin flake.lock

**Choice:** Commit `flake.lock` and remove all `--no-write-lock-file` flags.

**Why:** Without a lock file, CI resolves nixpkgs to whatever `nixos-unstable` points to *today*. A neovim or node update in nixpkgs could break CI without any code change. Pinning makes builds reproducible.

**Update process:** Run `nix flake update` explicitly and commit the lock when bumping deps.

### 3. Contract fixtures as JSON files, not inline

**Choice:** Store fixture payloads in `tools/neph-cli/tests/fixtures/*.json`, load them in tests.

**Why:** JSON fixtures can be updated by capturing real agent output (`neph gate --agent claude --dry-run` or from hook logs). Inline test data drifts from reality. Separate files make it obvious when a fixture needs updating.

### 4. Pre-push hook (not pre-commit)

**Choice:** `.githooks/pre-push` running `task check`, not pre-commit.

**Why:** Pre-commit runs on every commit, which is annoying during WIP. Pre-push is the last gate before code leaves the machine — fast enough to not be disruptive, late enough to catch real issues. Developers opt in via `git config core.hooksPath .githooks`.

### 5. tsc in check but not in pre-commit

**Choice:** `task check` includes `tsc --noEmit` for neph-cli only.

**Why:** tsc takes 2-3s which is acceptable for a push gate. Pi uses deno lint (no tsc). Adding tsc gives type-level confidence that the gate parsers haven't regressed.

## Risks / Trade-offs

- [Single job means no partial pass] If lint passes but tests fail, you can't see the lint result independently. Mitigation: the job outputs are still visible in step-level logs. Lint runs first so it fails fast.
- [Pre-push hook requires opt-in] Developers must run `git config core.hooksPath .githooks`. Mitigation: document in README, and `task check` works standalone regardless.
- [Fixture staleness] Agent JSON formats can change upstream without notice. Mitigation: fixtures fail loudly (test failure), and updating a fixture is a single file change.
