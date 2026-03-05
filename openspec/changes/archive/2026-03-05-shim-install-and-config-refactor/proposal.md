## Why

`neph.nvim` manages AI agent terminals but its companion tooling — the `nvim-shim` bash script (neovim RPC bridge for agents), `shim.py` (Python msgpack-rpc shim), and `pi.ts` (pi coding-agent extension) — live outside this repo in a personal dotfiles config. This creates a fragile dependency: the tools must be manually kept in sync, and any user installing `neph.nvim` misses the integration entirely. Additionally, `init.lua` conflates default configuration with setup logic, and the multiplexer backend is auto-detected with no way to override it.

## What Changes

- **Migrate tooling into neph.nvim**: Copy `nvim-shim` (bash), `shim.py` (Python msgpack-rpc), and `pi.ts` (pi extension) into a `tools/` directory in this repo.
- **Auto-install via neph.setup()**: On `setup()`, neph symlinks `shim.py` → `~/.local/bin/shim` and `pi.ts` → `~/.pi/agent/extensions/nvim.ts` (mirroring the `ai-shim.lua` pattern from sysinit.nvim, but now managed entirely by neph).
- **Extract defaults to `config.lua`**: Move the `defaults` table and type annotations out of `init.lua` into a dedicated `lua/neph/config.lua`, keeping `init.lua` thin.
- **Explicit multiplexer selection**: Replace the auto-detection heuristic in `session.lua` with a user-configurable `multiplexer` option: `"native"`, `"wezterm"`, `"tmux"` (commented stub), `"zellij"` (commented stub). Auto-detection remains as the default (`nil` → auto).
- **Consolidate AI plugins in sysinit.nvim**: Merge separate AI plugin specs into a single `ai.lua` plugin file. *(Out of scope for this repo; noted as a sysinit.nvim follow-up.)*

## Capabilities

### New Capabilities

- `tool-install`: neph.nvim ships `tools/nvim-shim`, `tools/shim.py`, and `tools/pi.ts`; `setup()` auto-symlinks them to their expected locations (`~/.local/bin/shim`, `~/.pi/agent/extensions/nvim.ts`).
- `multiplexer-config`: Users can explicitly set `multiplexer = "native" | "wezterm" | "tmux" | "zellij"` in opts; `nil` retains current auto-detection behavior. `tmux` and `zellij` backends are scaffolded as stub modules.
- `config-module`: Plugin defaults and the `neph.Config` type are defined in `lua/neph/config.lua`; `init.lua` imports from there.

### Modified Capabilities

*(none — no existing spec-level behavior changes)*

## Impact

- **`lua/neph/init.lua`**: Remove `defaults` table and type defs; import from `config.lua`.
- **`lua/neph/config.lua`** (new): Owns default values and `neph.Config` / `neph.FileRefreshConfig` type annotations.
- **`lua/neph/session.lua`**: `detect_backend()` respects the new `multiplexer` config key; explicit values short-circuit auto-detection.
- **`lua/neph/backends/tmux.lua`** (new stub): Scaffold matching the backend interface.
- **`lua/neph/backends/zellij.lua`** (new stub): Same as tmux stub.
- **`tools/nvim-shim`** (new): Copied from `~/.local/bin/nvim-shim`.
- **`tools/shim.py`** (new): Copied from `~/.config/nvim/tools/shim.py`.
- **`tools/pi.ts`** (new): Copied from `~/.config/nvim/tools/pi.ts`.
- **No breaking API changes** to `M.setup(opts)` — all new keys are optional with backward-compatible defaults.
