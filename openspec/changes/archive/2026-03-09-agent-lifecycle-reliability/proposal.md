## Why

Terminal agents (claude, goose, codex, crush) have no backchannel to Neovim. Once spawned, neph doesn't know if they're alive, ready, or if the neph-cli gate can still reach the Neovim socket. Text sent before an agent is ready gets lost; dead panes go undetected until the user happens to trigger CursorHold; and gate silently fails open when the socket is stale — all without user-visible feedback.

## What Changes

- Add `ready_pattern` field to `AgentDef` — a Lua pattern matched against terminal output to detect when an agent is accepting input
- Implement terminal output watching in both snacks and WezTerm backends to detect the ready transition
- Replace the blind 50ms×20 retry loop in `ensure_active_and_send` with a proper ready-state queue that waits for the ready signal
- Add `FocusGained` autocmd to session health checks so dead panes are detected when the user returns to Neovim (not just on CursorHold)
- Emit a visible stderr warning from neph-cli gate when it cannot connect to Neovim, instead of silently auto-accepting
- Unify `vim.g.{name}_active` state management: extension agents via bus, terminal agents via lifecycle tracking, with a single query API

## Capabilities

### New Capabilities
- `agent-lifecycle`: Agent lifecycle state machine (SPAWNED → READY → DEAD), ready-pattern detection, health checking, and unified state tracking across both backends

### Modified Capabilities
- `agent-bus`: Bus health timer and state management now participate in unified lifecycle tracking
- `runtime-agent-config`: AgentDef gains `ready_pattern` optional field

## Impact

- `lua/neph/internal/session.lua` — lifecycle state, ready queue, FocusGained autocmd
- `lua/neph/backends/snacks.lua` — terminal output watching via `on_data`
- `lua/neph/backends/wezterm.lua` — terminal output watching via `wezterm cli get-text`
- `lua/neph/internal/bus.lua` — integrate with unified lifecycle state
- `lua/neph/config.lua` — `ready_pattern` on AgentDef type
- `lua/neph/internal/contracts.lua` — validate `ready_pattern` as optional string
- `tools/neph-cli/src/gate.ts` — stderr warning on socket failure
- `tools/neph-cli/src/transport.ts` — surface connection errors
- Agent definition files (`claude.lua`, `goose.lua`, `codex.lua`, `crush.lua`) — add `ready_pattern`
