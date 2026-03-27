## Why

The neph.nvim TypeScript tools (neph CLI, amp plugin, pi harness) ship as pre-built bundles in `dist/`, but those bundles can become stale after a `:Lazy update` and there is no automated way for users to rebuild them. Similarly, the `~/.local/bin/neph` symlink that agents depend on for RPC has no lifecycle management — if it disappears (clean environment, new machine, Nix rebuild), every agent write silently rejects with no UI. Adding a lazy.nvim `build` hook (analogous to blink.cmp's `build = 'cargo build --release'`) closes this gap: build artifacts are (re)compiled and the CLI is symlinked automatically on every install or update.

## What Changes

- Add a `build` script at the plugin root (`scripts/build.sh`) that runs `npm ci && npm run build` for each TypeScript tool package and installs the CLI symlink.
- Add a Lua `build` function (`lua/neph/build.lua`) so the lazy.nvim spec can use either `build = 'bash scripts/build.sh'` (shell) or `build = function() require('neph.build').run() end` (Lua).
- Expose a Vimscript-compatible `:NephBuild` command for manual re-runs.
- Update the lazy.nvim plugin spec in the docs and README with the `build` key.
- Update `checkhealth neph` to report whether build artifacts are current (dist mtime vs src mtime).

## Capabilities

### New Capabilities

- `plugin-build`: Automated build pipeline invokable from lazy.nvim `build =`, `:NephBuild`, or `task build`. Compiles all TypeScript tool packages, installs `~/.local/bin/neph` symlink, and reports success/failure.

### Modified Capabilities

- `cli-install`: The existing `tools.install_cli()` / auto-repair path is extended so the build step can call it directly; `checkhealth` gains a stale-artifact check.

## Impact

- `scripts/build.sh` — new shell script (portable; works with `node` or `bun`)
- `lua/neph/build.lua` — new Lua module for the build entrypoint
- `lua/neph/init.lua` — register `:NephBuild` command
- `lua/neph/health.lua` — add artifact-staleness check
- `lua/neph/internal/tools.lua` — expose `dist_is_current()` helper
- `~/.config/nvim/lua/sysinit/plugins/neph.lua` — add `build` key to lazy spec
- `README.md` / docs — document build step in quick-start
- No breaking changes; all new keys are optional
