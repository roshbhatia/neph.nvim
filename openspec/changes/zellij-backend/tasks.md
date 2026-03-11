# Zellij Backend – Tasks

## 1. Session Refactor

- [x] 1.1 Add optional `backend.send(td, text, opts)` dispatch in `session.lua` M.send: if backend.send exists, call it and return; else use existing pane_id/buf logic
- [x] 1.2 Add optional `backend.single_pane_only` handling in `session.lua` M.open: if true, kill all other visible agents before opening
- [x] 1.3 Extract wezterm send logic from session into `wezterm.lua` as `M.send(td, text, opts)` using jobstart (no blocking)

## 2. Zellij Backend

- [x] 2.1 Create `lua/neph/backends/zellij.lua` with setup, open, focus, hide, is_visible, kill, cleanup_all
- [x] 2.2 Implement open: FIFO creation, jobstart(cat fifo), jobstart(zellij run ...), capture pane_id from on_stdout, cleanup FIFO
- [x] 2.3 Implement send: move-focus right, write-chars, move-focus left (via jobstart, async)
- [x] 2.4 Implement focus: move-focus right
- [x] 2.5 Implement kill/hide: move-focus left, move-focus right, close-pane (ensure on agent)
- [x] 2.6 Implement is_visible: list-clients, parse output, check pane_id
- [x] 2.7 Add single_pane_only = true, zellij_ready_delay_ms config
- [x] 2.8 Add ready timer (delay) instead of ready_pattern

## 3. Specs and Docs

- [x] 3.1 Add zellij backend scenario to openspec/specs/backend-submodules/spec.md
- [x] 3.2 Update AGENTS.md with Zellij backend section

## 4. Tests

- [x] 4.1 Add zellij backend to contract test (optional send, single_pane_only)
- [ ] 4.2 Manual test: Neovim in Zellij, zellij backend, open agent, send prompt
