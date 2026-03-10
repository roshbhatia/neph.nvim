## Context

Terminal agents are CLI processes spawned inside a pty (WezTerm pane or snacks terminal buffer). Neovim has no reliable way to know if the agent is alive, ready, or if the review gate can still reach the editor. Extension agents already have a persistent RPC channel via `bus.lua` with health checks. This design unifies lifecycle awareness across all agent types.

Current state:
- `session.lua` sets `vim.g.{name}_active = true` at spawn and clears it on kill, but never validates in between.
- `ensure_active_and_send` retries 50ms×20 checking `is_visible()` (pane/window exists), which says nothing about whether the agent process has loaded.
- `CursorHold` autocmd checks pane health, but only fires when the user moves the cursor — dead panes go unnoticed for long periods.
- `gate.ts` silently returns exit 0 (auto-accept) when it can't connect to Neovim.

## Goals / Non-Goals

**Goals:**
- Detect when terminal agents are ready to accept input (ready_pattern matching)
- Queue text until the agent is ready instead of fire-and-forget into the terminal
- Detect dead panes faster via FocusGained + timer-based health checks
- Warn users visibly when the gate can't reach Neovim
- Unify lifecycle state so `vim.g.{name}_active` reflects reality for all agent types

**Non-Goals:**
- Detecting agent busy/idle state (whether it's currently processing a prompt)
- Implementing ready detection for extension agents (bus.register already covers this)
- Adding a full state machine with transitions/events/observers — keep it simple

## Decisions

### 1. Ready pattern on AgentDef

Add optional `ready_pattern` (Lua string pattern) to `AgentDef`. Agents declare what their "ready for input" output looks like:

```lua
-- claude.lua
ready_pattern = "^%s*>"          -- Claude shows "> " when ready

-- goose.lua
ready_pattern = "^%s*%(.-%)>"    -- Goose shows "( O)> " or similar

-- codex.lua
ready_pattern = "^%s*>"          -- Codex shows "> "

-- crush.lua
ready_pattern = "^%s*>"          -- Crush shows "> "
```

**Why Lua patterns over regex:** Everything else in the plugin uses Lua patterns. No external dependency needed. The patterns are simple enough that Lua patterns suffice.

**Alternative considered:** Watching for any output at all (not pattern-specific). Rejected because agent startup banners produce output well before the agent is actually ready.

### 2. Backend output watching

**Snacks backend:** Hook `on_data` callback when creating the terminal. Snacks/Neovim terminal jobs fire `on_stdout` with each chunk of pty output. Match each line against `ready_pattern`. Set a `ready` flag on `term_data` when matched.

**WezTerm backend:** Use `wezterm cli get-text --pane-id <id>` to capture the last N lines of the pane. Poll this on a timer after spawn (same pattern as the existing `wait_for_pane`). Once the pattern is found, mark ready and stop polling.

The WezTerm polling timer runs at 200ms intervals for up to 30 seconds (150 attempts). This is more generous than the current 500ms `wait_for_pane` because agent startup (npm, Python env, etc.) can be slow. After timeout, mark ready anyway (fail-open — don't block the user forever).

**Alternative considered:** Having neph-cli signal readiness by calling an RPC method from within the agent's shell. Rejected because terminal agents don't know about neph and we can't inject shell hooks into their TUI processes.

### 3. Ready queue in session.lua

Replace the blind retry loop in `ensure_active_and_send` with a callback-based ready queue:

```
session.open(name)
  → backend.open() returns term_data with ready=false
  → backend starts output watching
  → output matches ready_pattern
  → backend sets term_data.ready = true, fires on_ready callback
  → session drains queued text
```

If no `ready_pattern` is defined on the agent, `term_data.ready` is set to `true` immediately (backwards compatible — current behavior preserved for agents without patterns).

The queue is a simple list of `{text, opts}` per terminal name. On ready, drain the queue in order via `M.send()`. On kill, discard the queue.

### 4. Health check improvements

Add `FocusGained` to the existing `CursorHold` autocmd in session.lua. When Neovim regains focus (user was alt-tabbed or looking at the agent pane), check all tracked terminals for liveness. This catches the common case: user sees agent crash in WezTerm, switches back to Neovim, and neph immediately detects the dead pane.

No timer-based polling for terminal agents. The bus already has its 1s timer for extension agents. Terminal agent health relies on `CursorHold` + `FocusGained` + `is_visible()` checks before send. This avoids expensive `wezterm cli list` calls on a timer.

### 5. Gate stderr warning

In `gate.ts`, when transport is null (socket connection failed), write to stderr:

```
neph: WARNING — could not connect to Neovim (NVIM_SOCKET_PATH=/tmp/nvim.1234/0), auto-accepting file changes
```

This appears in the agent's terminal output (since neph-cli runs as a hook subprocess). The user will see it while watching the agent work.

Also log when `NVIM_SOCKET_PATH` is not set at all (currently it just falls through to `discoverNvimSocket` which may find a wrong instance).

### 6. Unified vim.g state

Current situation:
- Terminal agents: `vim.g.{name}_active` set in `session.open()`, cleared in `kill_session()`
- Extension agents: `vim.g.{name}_active` set in `bus.register()`, cleared in `bus.unregister()`

These two paths use the same global variable but with different semantics. Unify by having session.lua be the single writer:

- On `open()`: set `vim.g.{name}_active = true` for ALL agent types
- On `kill_session()`: clear for ALL agent types
- Bus registration/unregistration: no longer touches vim.g directly — only manages the channel map
- Health check (CursorHold/FocusGained): clears `vim.g.{name}_active` when pane is dead

This means `vim.g.{name}_active` always reflects "neph has an open terminal for this agent" regardless of type. Bus connection status is a separate concern queryable via `bus.is_connected()`.

## Risks / Trade-offs

**[WezTerm get-text polling is expensive]** → Mitigated by only polling during the startup window (max 30s after spawn), not continuously. Once ready or timed out, polling stops.

**[Ready patterns are fragile]** → Agent CLI updates could change prompt format. Mitigated by: fail-open on timeout (agent still works, just no ready guarantee), and patterns are in agent definition files that users can override.

**[FocusGained may not fire in all terminals]** → Some terminal emulators don't send focus events. CursorHold remains as fallback. This is strictly additive.

**[stderr warning clutters agent output]** → Only one line, only on failure. The alternative (silent auto-accept) is worse — user has no idea review is broken.
