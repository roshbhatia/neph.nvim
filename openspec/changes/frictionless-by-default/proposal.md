## Why

neph today optimizes for the *control* dimension (review gate, hooks, policy engine) but forces users to opt **in** to friction-removing affordances every time:

- Context is manual: users must type `+selection`, `+cursor`, etc. to inject editor state.
- Each agent has its own integration surface; nothing leverages off-the-shelf plugins like `claudecode.nvim` or `opencode.nvim` that already solve protocol/transport/broadcast cleanly.
- Defaults are conservative: review gate is `normal` (every write opens a UI), claude launches with `--permission-mode plan`, and there is no way to launch "fully open" without manual config.

The goal is to flip the default posture to "frictionless and open" — agents have ambient editor context, claude runs unblocked, the review gate stays out of the way unless explicitly engaged — while keeping every existing safety mechanism one keymap away.

## What Changes

- **NEW** `peer-adapter` capability: `type = "peer"` agents delegate session lifecycle, transport, and broadcasting to a third-party Neovim plugin (`claudecode.nvim`, `opencode.nvim`). neph composes its review queue, gate, and multi-agent UX **on top** of the peer plugin instead of reimplementing protocol work.
- **NEW** `auto-context-broadcast` capability: continuously snapshot active editor state (buffer, selection, visible files, diagnostics, cwd) to a well-known JSON file under `stdpath("state")/neph/context.json`, debounced on `CursorMoved`/`BufWinEnter`/`DiagnosticChanged`. Any agent — terminal, hook, peer, extension — can read fresh context without an explicit RPC round-trip.
- **MODIFIED** `agent-lifecycle`: extend the agent-type enum from `{hook, terminal, extension}` to `{hook, terminal, extension, peer}`. Peer agents skip backend launch and instead bind to a peer plugin's session API.
- **MODIFIED** `neph-cli`: add `neph context current` to print the latest broadcast snapshot for terminal agents that can't read the file directly.
- Flip `gate` default from `"normal"` to `"bypass"` (writes auto-accept; review pipeline still installed and one keymap away via `<leader>jg`).
- Update `agents/claude.lua` to launch with `--dangerously-skip-permissions` (drop `--permission-mode plan`).
- Add `agents/claude-peer.lua` and `agents/opencode-peer.lua` opt-in agent definitions that use the peer adapter.
- Add optional dependencies on `coder/claudecode.nvim` and `nickjvandyke/opencode.nvim`; both are gracefully absent (peer agents emit a one-time setup notice when their backing plugin is missing).

## Capabilities

### New Capabilities
- `peer-adapter`: contract and lifecycle for delegating agent sessions to an external Neovim plugin (claudecode.nvim, opencode.nvim) while keeping neph's review queue, gate, and multi-agent UX in charge.
- `auto-context-broadcast`: continuous, debounced snapshot of editor state to a well-known JSON file plus a CLI command that reads it.

### Modified Capabilities
- `agent-lifecycle`: adds `peer` to the agent-type enum and defines how peer agents skip backend lifecycle.
- `neph-cli`: adds `neph context current` subcommand.

## Impact

- **Lua plugin**:
  - `lua/neph/contracts.lua` — accept `type = "peer"` and a `peer` sub-table.
  - `lua/neph/internal/session.lua` — short-circuit backend launch for peer agents; route `send` through the peer adapter.
  - `lua/neph/peers/` (new) — adapter modules: `claudecode.lua`, `opencode.lua`, plus `init.lua` registry.
  - `lua/neph/internal/context_broadcast.lua` (new) — autocommand-driven JSON writer.
  - `lua/neph/agents/claude.lua` — drop `--permission-mode plan`, add `--dangerously-skip-permissions`.
  - `lua/neph/agents/claude-peer.lua` (new), `lua/neph/agents/opencode-peer.lua` (new) — opt-in definitions.
  - `lua/neph/config.lua` — flip default gate to `bypass`; add `context_broadcast` config key.
  - `lua/neph/init.lua` — start broadcaster after setup.
- **CLI**:
  - `tools/neph-cli/src/commands/context.ts` (new) — `neph context current`.
- **Docs**:
  - `README.md` — describe peer adapters, auto-context, and "open by default" posture; document optional deps.
- **Tests**:
  - `tests/` — peer adapter contract tests, broadcaster debounce + payload shape tests, CLI command tests.
- **External dependencies**: `claudecode.nvim` and `opencode.nvim` become **optional** peer dependencies (declared in lazy spec docs, not as hard requires). Loading either is gated on `pcall(require, ...)`.
