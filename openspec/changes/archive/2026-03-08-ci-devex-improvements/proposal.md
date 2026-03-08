## Why

The CI pipeline has 4 layers of indirection (GHA → Deno → Dagger → Nix), no caching, serial execution, and no auto-release. CI takes ~5-10 minutes on cold runs. There's no versioning, no changelog, no fast local feedback loop. The settings.json merge in tools.lua destructively overwrites the entire `hooks` key on every nvim startup, which will silently clobber user-configured hooks. These issues compound to create a fragile development experience where breakage isn't caught early and releases require manual effort.

## What Changes

- **Simplify CI from 4 layers to 2** — Replace Dagger/FluentCI with direct `nix develop -c task ci` in GitHub Actions, using Nix store caching via cachix
- **Parallelize CI jobs** — Split lint, test, and e2e into separate GHA jobs that run concurrently
- **Add auto-release** — Use release-please for conventional commit-driven version bumps, changelogs, and GitHub releases
- **Add fast local check** — New `task check` target for sub-2-second lint-only feedback
- **Fix settings merge to be additive** — `json_merge()` should deep-merge hook arrays instead of replacing the entire key
- **Add snacks.nvim to CI** — Include snacks.nvim in Nix flake so e2e agent launch tests actually exercise the native backend

## Capabilities

### New Capabilities
- `ci-pipeline`: Simplified, cached, parallel CI pipeline with Nix-direct GitHub Actions
- `auto-release`: Conventional commit linting and automated release-please workflow
- `local-fast-check`: Sub-2-second local lint/typecheck task for rapid feedback
- `safe-settings-merge`: Non-destructive JSON merge for agent hook configurations

### Modified Capabilities
- `tool-install`: Settings merge behavior changes from key replacement to additive array merge

## Impact

- **CI pipeline**: `.fluentci/ci.ts` removed; `.github/workflows/ci.yml` rewritten; `flake.nix` updated with snacks.nvim and cachix
- **Taskfile**: New `check` task; existing tasks unchanged
- **tools.lua**: `json_merge()` function rewritten for additive merge
- **New files**: `.github/workflows/release.yml`, commitlint config
- **Dependencies**: cachix GHA action (CI only); release-please GHA action (CI only)
- **No runtime changes to plugin API**
