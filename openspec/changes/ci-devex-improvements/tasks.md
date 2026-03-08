## 1. CI Pipeline Simplification

- [x] 1.1 Rewrite `.github/workflows/ci.yml` — replace Dagger with 3 parallel jobs (lint, test, e2e) each running `cachix/install-nix-action` + `nix develop -c task <target>`
- [x] 1.2 Add Nix store caching via `cachix/cachix-action` or GHA cache action with `/nix/store` path
- [x] 1.3 Add `vimPlugins.snacks-nvim` to `flake.nix` devShell buildInputs and export `SNACKS_PATH` in shellHook
- [x] 1.4 Update `tests/e2e/run.lua` and `tests/e2e/launch_one.lua` to use `SNACKS_PATH` env var for snacks.nvim runtimepath
- [x] 1.5 Remove `.fluentci/ci.ts` and `task dagger` from Taskfile (Dagger no longer used)

## 2. Safe Settings Merge

- [x] 2.1 Rewrite `json_merge()` in `lua/neph/tools.lua` to do additive hook array merge — match on hook event type and matcher/command to detect duplicates, append new entries, preserve existing
- [x] 2.2 Add e2e test for additive merge — verify that existing hooks survive `tools.install()` and neph hooks are added without duplication

## 3. Auto-Release

- [x] 3.1 Create `.github/workflows/release.yml` with release-please action, configured for simple (non-monorepo) Lua plugin
- [x] 3.2 Add `release-please-config.json` and `.release-please-manifest.json` with initial version
- [ ] 3.3 Verify release-please workflow creates a release PR on feat/fix commits (manual test after push)

## 4. Local Fast Check

- [x] 4.1 Add `task check` to root Taskfile.yml — runs `stylua --check lua/ tests/` and `luacheck lua/ tests/` only (no tests, no builds)

## 5. Validation

- [x] 5.1 Run `task check` locally — verify it completes in under 2 seconds
- [x] 5.2 Run `task ci` locally via `nix develop -c task ci` — verify lint + test + e2e all pass
- [ ] 5.3 Push to GitHub — verify all 3 parallel CI jobs pass
- [ ] 5.4 Verify release-please bot creates a release PR
