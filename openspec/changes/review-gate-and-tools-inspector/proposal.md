## Why

Users running AI agents in "let it rip" sessions have no runtime control over the review pipeline — reviews fire immediately on every file write with no way to pause, accumulate, or bypass them without touching config. Separately, there is no visibility from inside Neovim (or the CLI) into which agent tool integrations are installed vs missing, making it opaque why an agent like amp shows "plugin failing."

## What Changes

- Add a global **review gate** with three states: `normal` (current behavior), `hold` (accumulate reviews silently, drain on release), and `bypass` (auto-accept all hunks, no UI). Toggleable from both Neovim keymaps/API and the neph-cli.
- Add a **tools inspector** accessible from Neovim (`:NephStatus` buffer + keymap) and neph-cli (`neph tools status`, `neph tools install`, `neph tools preview`) showing per-agent filesystem install state and runtime integration pipeline.
- Add **symmetric CLI↔Neovim control**: CLI commands for gate and tools operations are thin RPC wrappers that drive Neovim state via `nvim --server $NVIM_SOCKET_PATH`, matching the pattern already used by the review protocol.
- **Documentation updates**: README, agent authoring guide, and LuaDoc annotations updated to cover gate API, CLI commands, and tools inspector UX.

## Capabilities

### New Capabilities

- `review-gate`: Global runtime toggle for the review pipeline — three states (normal / hold / bypass), driven from both `neph.api` and neph-cli, with statusline integration and keymap surface.
- `tools-inspector`: Per-agent visibility into filesystem tool install state (symlinks, json merges, builds) and runtime integration pipeline; includes install/uninstall/preview actions from Neovim and CLI.
- `cli-gate-commands`: neph-cli subcommands (`neph gate hold|bypass|release|status`) as RPC thin clients over `NVIM_SOCKET_PATH`.
- `cli-tools-commands`: neph-cli subcommands (`neph tools status|install|uninstall|preview`) combining filesystem checks with optional Neovim pipeline introspection.

### Modified Capabilities

- `review-queue`: Gate state (hold/bypass) must be respected by the queue drain mechanism — hold pauses the drain, bypass short-circuits enqueue to auto-accept.
- `neph-cli`: New top-level subcommand groups `gate` and `tools` added alongside existing review protocol commands.
- `lua-api-layer`: `neph.api` gains `gate()` / `gate_status()` functions; statusline gains gate state rendering.

## Impact

- **`lua/neph/internal/gate.lua`** — new module owning gate state and providing `set(state)`, `get()`, `release()`
- **`lua/neph/internal/review_queue.lua`** — drain loop reads gate state; hold pauses pop, bypass auto-accepts on enqueue
- **`lua/neph/api.lua`** — new `api.gate()` (cycle), `api.gate_hold()`, `api.gate_bypass()`, `api.gate_release()`, `api.tools_status()`
- **`lua/neph/api/status.lua`** — gate state rendered in statusline component
- **`lua/neph/internal/tools.lua`** — new `M.status(root, agents)` returning per-agent install state table
- **neph-cli TypeScript** — new `gate` and `tools` command groups; RPC calls via `nvim --server`
- **`~/.config/nvim/.../neph.lua`** (user config) — new keymaps for gate toggle and status
- **`README.md`, `doc/neph.txt`** — gate toggle UX, CLI commands, tools inspector documented
- No breaking changes to existing API signatures or config schema
