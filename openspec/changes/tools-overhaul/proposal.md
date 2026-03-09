## Why

The current tool installation system (`tools.lua`) generates a monolithic shell script and runs it via `sh -c`. This is fragile: a single failure (even a non-error like `[ -e /missing ] && ...` returning exit 1) kills the entire install, the error message gives zero context ("Neph tool install had errors"), and there's no way for users to manually manage installations. There's also no checkhealth integration to diagnose what's installed vs broken.

## What Changes

- **BREAKING**: Rewrite `tools.lua` to use pure Lua operations instead of generating shell scripts. Each agent's install is independent — one failure doesn't block others.
- Add `:NephTools` user command with subcommands: `install [all|<agent>]`, `uninstall [all|<agent>]`, `reinstall [all|<agent>]`, `status`
- Add `checkhealth` integration (`lua/neph/health.lua`) reporting tool install status, symlink health, build artifact freshness, and agent availability
- Per-agent error reporting with actionable messages (e.g., "neph-cli: build failed — npm not found")
- `install <agent>` works even if agent isn't on PATH (explicit intent overrides the PATH filter)
- JSON unmerge support for clean uninstall of hook configurations

## Capabilities

### New Capabilities

- `tools-commands`: `:NephTools` user command with install/uninstall/reinstall/status subcommands and tab completion
- `tools-checkhealth`: Neovim checkhealth integration for diagnosing tool installation state

### Modified Capabilities

- `tool-install`: Rewrite from shell script generation to pure Lua per-agent operations with independent error handling
- `selective-install`: `install <agent>` bypasses PATH check for explicit installs; `install all` still respects PATH

## Impact

- `lua/neph/tools.lua` — full rewrite: pure Lua install/uninstall operations, per-agent stamp files, independent error handling
- `lua/neph/health.lua` — new file: checkhealth provider
- `lua/neph/init.lua` — register `:NephTools` user command
- `lua/neph/config.lua` — add `undo` and `submit` keymap types if not already present
- `tests/api/review/` — no changes (different module)
- `tests/tools_test.lua` — update tests for new install/uninstall API
