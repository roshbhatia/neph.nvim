## 1. Scaffolding

- [ ] 1.1 Extend `lua/neph/internal/contracts.lua` to accept `type = "peer"` and a `peer` sub-table with required `kind` field
- [ ] 1.2 Create `lua/neph/peers/init.lua` registry with `resolve(kind)` lazy loader
- [ ] 1.3 Create `lua/neph/peers/claudecode.lua` skeleton implementing the six-function adapter contract (open/send/kill/is_visible/focus/hide) with `is_available()` checking `pcall(require, "claudecode")`
- [ ] 1.4 Create `lua/neph/peers/opencode.lua` skeleton with the same surface, checking `pcall(require, "opencode")`
- [ ] 1.5 Add unit tests for `peers.resolve` (known kind, unknown kind, plugin-absent path)

## 2. Session dispatch for peer agents

- [ ] 2.1 In `lua/neph/internal/session.lua`, branch on `agent.type == "peer"` in `open()` to call `peers.resolve(agent.peer.kind).open(...)` instead of the configured backend
- [ ] 2.2 Branch in `send()` so peer agents route through the adapter's `send`
- [ ] 2.3 Branch in `kill()`, `is_visible()`, `focus()`, `hide()` to dispatch through the adapter
- [ ] 2.4 Emit a one-shot notification per session when an adapter's `is_available()` returns false
- [ ] 2.5 Add session tests covering the peer dispatch path with a fake adapter

## 3. Auto-context broadcaster

- [ ] 3.1 Create `lua/neph/internal/context_broadcast.lua` with `setup(opts)` that registers debounced autocommands on `CursorMoved`, `CursorMovedI`, `BufWinEnter`, `BufWinLeave`, `WinClosed`, `DiagnosticChanged`, `DirChanged`
- [ ] 3.2 Implement snapshot builder that produces the JSON shape defined in `specs/auto-context-broadcast/spec.md` (reuse the source-window filter from `lua/neph/internal/context.lua`)
- [ ] 3.3 Write the snapshot atomically: write to a sibling temp file, then `vim.uv.fs_rename` to the target
- [ ] 3.4 Add `context_broadcast = { enable = true, debounce_ms = 50, include_clipboard = false }` to `config.defaults` and validation
- [ ] 3.5 Wire `setup()` in `lua/neph/init.lua` to start the broadcaster after agents/session are initialised
- [ ] 3.6 Tests: snapshot shape, debounce behaviour, source-window filter, atomic write, disabled-by-config no-op

## 4. claudecode peer adapter — full implementation

- [ ] 4.1 In `peers/claudecode.lua`, `open()` SHALL call `require("claudecode").start()` (idempotent — claudecode handles repeat calls), then send the prompt through claudecode's terminal API
- [ ] 4.2 Implement `send()` by calling `require("claudecode").send_at_mention(...)` or the equivalent broadcast text path; on visual selections, prefer the at-mention API to preserve range info
- [ ] 4.3 Implement `kill()` to call claudecode's stop/close terminal command
- [ ] 4.4 Implement `is_visible`, `focus`, `hide` by delegating to claudecode's terminal toggle/focus commands
- [ ] 4.5 When `agent.peer.override_diff == true`, monkey-patch `require("claudecode.tools").handlers.openDiff` with a function that captures `(oldFile, newFile, content, description)` and enqueues `review_queue.enqueue({ source = "claudecode", file = newFile, ... })`
- [ ] 4.6 Capture the deferred MCP response handle and resolve it from the review queue's accept/reject callback
- [ ] 4.7 Add an integration smoke test that loads a stub `claudecode` module (since the real plugin isn't installed in CI) and verifies the override fires

## 5. opencode peer adapter — full implementation

- [ ] 5.1 In `peers/opencode.lua`, `open()` SHALL call `require("opencode")` setup if needed and ensure the server is started via `require("opencode").start()`
- [ ] 5.2 Implement `send()` to call `require("opencode").prompt(text, opts)`
- [ ] 5.3 Implement `kill()` via `require("opencode").stop()`
- [ ] 5.4 Implement `is_visible`/`focus`/`hide` via opencode's session UI APIs
- [ ] 5.5 Stub-module integration test mirroring task 4.7

## 6. New peer agent definitions

- [ ] 6.1 Create `lua/neph/agents/claude-peer.lua` with `type = "peer"`, `peer = { kind = "claudecode", override_diff = true }`
- [ ] 6.2 Create `lua/neph/agents/opencode-peer.lua` with `type = "peer"`, `peer = { kind = "opencode" }`
- [ ] 6.3 Add both to `lua/neph/agents/all.lua` so they appear in the picker by default (users can drop them via custom `agents` lists)
- [ ] 6.4 Tests: contract validation accepts the new definitions; picker exposes them when their adapters are available

## 7. Open-by-default defaults

- [ ] 7.1 In `lua/neph/internal/gate.lua`, change the initial `state` to `"bypass"`
- [ ] 7.2 In `lua/neph/agents/claude.lua`, change `args` from `{"--permission-mode", "plan"}` to `{"--dangerously-skip-permissions"}`
- [ ] 7.3 In `config.defaults`, surface `gate = "bypass"` explicitly so users see it in their resolved config
- [ ] 7.4 Update `lua/neph/internal/gate_ui.lua` initial render to reflect bypass-by-default state
- [ ] 7.5 Add tests verifying the new defaults
- [ ] 7.6 Update `README.md` "Review Gate" section to document the new default and how to opt back in (`<leader>jg`, `:NephGate normal`, neoconf override)

## 8. CLI command

- [ ] 8.1 Add `tools/neph-cli/src/commands/context.ts` implementing `context current` with the flags `--max-age-ms`, `--field`
- [ ] 8.2 Register the command in `tools/neph-cli/src/main.ts` (or wherever the command tree lives)
- [ ] 8.3 Add Vitest tests covering fresh / missing / stale / field-extract paths
- [ ] 8.4 Run `task tools:lint:neph` and `task tools:test:neph` to confirm the bundle builds clean

## 9. Documentation and release

- [ ] 9.1 Update `README.md` lazy spec example to show optional peer plugin installs
- [ ] 9.2 Add a "Peer adapters" section explaining when to use `claude-peer` vs `claude`
- [ ] 9.3 Document the broadcast file path and `neph context current` in the README
- [ ] 9.4 Add a `MIGRATION.md` (or CHANGELOG) note for the gate/permissions default flip

## 10. Manual verification in wezterm

- [ ] 10.1 Verify hook `claude` agent: opens, sends prompt, gate=bypass auto-accepts a write
- [ ] 10.2 Verify terminal `goose` agent: opens, sends prompt, fs_watcher catches a write, gate=bypass auto-accepts
- [ ] 10.3 Verify extension `pi` agent: bus connects, prompt routes through bus
- [ ] 10.4 Verify peer `claude-peer` agent (requires claudecode.nvim installed): opens, sends prompt, openDiff routes through neph review queue
- [ ] 10.5 Verify peer `opencode-peer` agent (requires opencode.nvim installed): opens, sends prompt
- [ ] 10.6 Verify `neph context current` returns fresh data while editor is open
- [ ] 10.7 Verify `<leader>jg` cycles through bypass → normal → hold → bypass and the winbar indicator updates
