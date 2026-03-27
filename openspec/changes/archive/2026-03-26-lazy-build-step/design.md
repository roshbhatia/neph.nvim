## Context

neph.nvim ships TypeScript tools (`tools/neph-cli`, `tools/amp`, `tools/pi`) as esbuild bundles committed to `dist/`. Users who install the plugin via lazy.nvim get those bundled files directly, which is fine at install time but becomes stale after a `:Lazy update` that pulls new source without recompiling. Additionally, the `~/.local/bin/neph` symlink that agents rely on for spawning the CLI has no lifecycle hook — it disappears silently in clean/Nix environments.

The current auto-repair in `setup()` handles the symlink, but it cannot rebuild stale TypeScript bundles, and it fires every Neovim startup rather than only on plugin install/update.

## Goals / Non-Goals

**Goals:**
- Provide a `build` entry in the lazy.nvim plugin spec (shell string and Lua function variants) that compiles all TS tools and installs the CLI symlink
- Add `:NephBuild` command for manual re-runs inside Neovim
- Add `checkhealth` staleness detection comparing `dist/` mtime to `src/` mtime
- Document the build step in README quick-start

**Non-Goals:**
- Bundling a Node/npm runtime — users are expected to have `node` and `npm` available (same requirement that already exists for the CLI to run)
- Supporting every package manager (pnpm, bun, yarn) — `npm ci` is the canonical build command; users can override via config
- Cross-compiling or producing platform binaries

## Decisions

**Shell script vs. pure Lua build runner**
Use a thin `scripts/build.sh` as the primary build driver so lazy.nvim's `build = 'bash scripts/build.sh'` works without any Lua loaded. The Lua module `lua/neph/build.lua` is a thin wrapper that shells out to the same script, enabling the `build = function() ... end` variant and `:NephBuild`. Both paths are equivalent.

**npm ci vs. npm install**
Use `npm ci` (reproducible, uses lockfile) for the build step. `dist/` files are still committed so offline installs without Node work for users who don't call the build step.

**Staleness heuristic in checkhealth**
Compare the newest `src/**/*.ts` mtime against the `dist/index.js` mtime using `vim.uv.fs_stat`. This is a best-effort check — it catches the common "updated but didn't rebuild" case without requiring a full dependency graph.

**`:NephBuild` command**
Registered in `init.lua` alongside `:NephInstall`. Runs the build asynchronously via `vim.system` so Neovim doesn't block. Outputs progress via `vim.notify`.

**doc update scope**
Update `README.md` quick-start snippet and `doc/neph.txt` (vimdoc) to show the `build` key. No API doc changes needed.

## Risks / Trade-offs

- If `node`/`npm` are not on PATH when lazy runs the build hook, the build silently fails and `dist/` remains at the last committed version. The health check will surface this.
- `npm ci` is slow (~5-10s on a cold cache). The build only runs on install/update, not on every startup, so this is acceptable.
- Committing `dist/` to the repo means the plugin works without Node for users who never modify the TS source. The build step is additive, not required.
