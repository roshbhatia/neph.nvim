## 1. AgentDef type and contracts

- [x] 1.1 Add `ready_pattern` optional field to `neph.AgentDef` class annotation in `lua/neph/config.lua`
- [x] 1.2 Add `ready_pattern = "string"` to `AGENT_OPTIONAL_FIELDS` in `lua/neph/internal/contracts.lua`

## 2. Agent definitions

- [x] 2.1 Add `ready_pattern = "^%s*>"` to `lua/neph/agents/claude.lua`
- [x] 2.2 Add `ready_pattern = "^%s*%(.-%)>"` to `lua/neph/agents/goose.lua`
- [x] 2.3 Add `ready_pattern = "^%s*>"` to `lua/neph/agents/codex.lua`
- [x] 2.4 Add `ready_pattern = "^%s*>"` to `lua/neph/agents/crush.lua`

## 3. Backend ready detection — Snacks

- [x] 3.1 Modify `lua/neph/backends/snacks.lua:open()` to accept `ready_pattern` in agent_config and hook `on_stdout` on the terminal job to match output lines against the pattern
- [x] 3.2 Set `term_data.ready = true` on first match; set `term_data.ready = true` immediately if no pattern
- [x] 3.3 Add a 30-second timeout timer that sets `term_data.ready = true` if no match (fail-open)
- [x] 3.4 Fire `term_data.on_ready()` callback when ready becomes true (session.lua will set this)

## 4. Backend ready detection — WezTerm

- [x] 4.1 Modify `lua/neph/backends/wezterm.lua:open()` to accept `ready_pattern` in agent_config and start a 200ms polling timer that runs `wezterm cli get-text --pane-id <id>`
- [x] 4.2 Match each line of the captured text against the pattern; set `term_data.ready = true` on first match
- [x] 4.3 Stop polling on match or after 30 seconds (150 attempts); fire `term_data.on_ready()` callback
- [x] 4.4 Set `term_data.ready = true` immediately if no pattern provided

## 5. Session ready queue

- [x] 5.1 Add `ready_queue` table (`table<string, {text:string, opts:table}[]>`) to `session.lua` module state
- [x] 5.2 Pass `ready_pattern` from agent definition through `agent_config` to backend in `session.open()`
- [x] 5.3 Set `term_data.on_ready` callback in `session.open()` that drains the ready queue via `M.send()`
- [x] 5.4 Rewrite `ensure_active_and_send` to check `term_data.ready`; if not ready, push to queue; if ready, send immediately
- [x] 5.5 Clear the queue entry for a terminal in `kill_session()`

## 6. Health check improvements

- [x] 6.1 Add `FocusGained` to the existing `CursorHold` autocmd in `session.lua` setup
- [x] 6.2 In the health check callback, also clear `vim.g.{name}_active` when a dead pane is detected

## 7. Unified vim.g state

- [x] 7.1 In `session.open()`, set `vim.g.{name}_active = true` for ALL agent types (remove the `if not agent.type` guard)
- [x] 7.2 In `session.kill_session()`, clear `vim.g.{name}_active` for ALL agent types (remove the `if agent and not agent.type` guard)
- [x] 7.3 Remove `vim.g[name .. "_active"] = true` from `bus.register()` in `bus.lua`
- [x] 7.4 Remove `vim.g[name .. "_active"] = nil` from `bus.unregister()` in `bus.lua`
- [x] 7.5 Remove the `vim.g` cleanup loop from `bus.cleanup_all()` (session.lua VimLeavePre handler already clears state)

## 8. Gate stderr warning

- [x] 8.1 In `tools/neph-cli/src/gate.ts`, when transport is null, write a warning to stderr with the socket path (or "not set")
- [x] 8.2 In `tools/neph-cli/src/index.ts`, when `SocketTransport` constructor fails, surface the error message to gate instead of silently returning null

## 9. Tests

- [x] 9.1 Add test that `ready_pattern` is accepted by contract validation
- [x] 9.2 Add test that agent definitions with `ready_pattern` pass validation
- [x] 9.3 Add session test: agent without `ready_pattern` has `term_data.ready = true` immediately
- [x] 9.4 Add session test: `ensure_active_and_send` queues text when `term_data.ready` is false
- [x] 9.5 Add session test: queue is drained when `on_ready` fires
- [x] 9.6 Add session test: queue is discarded on `kill_session`
- [x] 9.7 Add gate test: stderr warning emitted when transport is null
