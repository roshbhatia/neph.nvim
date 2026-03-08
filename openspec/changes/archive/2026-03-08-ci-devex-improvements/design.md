## Context

The current CI pipeline uses 4 layers: GitHub Actions → Deno → Dagger SDK → Nix container. Each `withExec` re-enters `nix develop`, there's no caching, and lint/test run serially. The project has no versioning, no changelog, and no auto-release. Locally, there's no fast-feedback task — `task ci` runs everything serially including tests.

The `json_merge()` in tools.lua does `dst_json[key] = src_json[key]` which replaces the entire hooks key. If a user has other hooks configured (or their settings are symlinked from a dotfiles repo), neph will overwrite them on every nvim startup.

## Goals / Non-Goals

**Goals:**
- CI completes in under 2 minutes with caching
- Lint, test, and e2e run in parallel CI jobs
- Conventional commits enforced; auto-release on merge to main
- Local `task check` completes in under 2 seconds
- Settings merge is additive — neph's hooks are appended, not replacing
- E2e agent launch tests use snacks.nvim in CI

**Non-Goals:**
- Migrating away from Nix (Nix is good, the Dagger wrapper isn't needed)
- LuaRocks publishing (can be added later)
- Coverage enforcement thresholds
- Pre-commit hooks (rely on CI for enforcement)

## Decisions

### 1. Drop Dagger, use Nix directly in GHA

Replace `.fluentci/ci.ts` with a direct `nix develop -c task ci` in the GHA workflow. Dagger adds complexity with no benefit for this project — all it does is run commands in a Nix container, which GHA + `cachix/install-nix-action` does natively.

**Why not keep Dagger**: Every `.withExec` re-enters `nix develop`. There's no layer caching being used. The Dagger SDK requires Deno which is another dependency. The `process.exit(0)` workaround for "Dagger SDK session teardown crash on Deno v2" is a red flag.

**Alternatives considered:**
- Keep Dagger but add caching → still 4 layers, still slow
- Plain GHA without Nix → loses reproducible environment

### 2. Parallel CI jobs via GHA matrix or separate jobs

Split into 3 parallel jobs: lint, test (unit + e2e smoke), e2e-agents. Each runs `nix develop -c task <target>`. Total wall time is the max of the three, not the sum.

### 3. release-please for auto-release

Google's release-please bot watches main for conventional commits, maintains a release PR with changelog, and creates GitHub releases on merge. It's well-maintained, handles monorepo-like setups, and requires zero config beyond the workflow file.

**Why not semantic-release**: release-please creates a visible PR before releasing, giving a chance to review. semantic-release is fire-and-forget on merge.

### 4. Additive hook merge via array concatenation

Change `json_merge()` to:
1. Read existing hooks from destination
2. For each hook matcher in source, check if it already exists in destination
3. If not present, append it
4. If present with same command, skip (idempotent)
5. Never remove existing hooks

This makes `tools.install()` safe to call repeatedly without clobbering user config.

### 5. Add snacks.nvim to flake.nix

Add `vimPlugins.snacks-nvim` (or fetch from GitHub if not in nixpkgs) to the Nix dev shell. Set `SNACKS_PATH` env var. Update e2e launch tests to add it to runtimepath.

### 6. Fast local check task

New `task check` that runs only:
- `stylua --check lua/ tests/`
- `luacheck lua/ tests/` (if available)

No tests, no builds. Under 2 seconds. For quick pre-push validation.

## Risks / Trade-offs

- **Dagger removal** → Loses ability to run CI exactly as it runs remotely (via `task dagger`). Mitigate: `nix develop -c task ci` achieves the same thing locally.
- **release-please bot** → Adds a bot-maintained PR that must be merged to release. Some find this noisy. Mitigate: It auto-updates, only need to merge when ready to release.
- **Additive merge complexity** → Hook array matching is more complex than key replacement. Mitigate: Match on `matcher` field to detect duplicates, keep logic simple.
- **snacks.nvim in CI** → May not be in nixpkgs yet. Mitigate: Use `fetchFromGitHub` in flake.nix as fallback.
