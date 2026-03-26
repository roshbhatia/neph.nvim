## 1. Gate Module (Lua)

- [ ] 1.1 Create `lua/neph/internal/gate.lua` with `get()`, `set(state)`, `release()` and state validation
- [ ] 1.2 Add LuaDoc/EmmyLua annotations and `---@type` for gate state enum
- [ ] 1.3 Wire `review_queue.enqueue()` to check `gate.get()`: hold suppresses `open_fn`, bypass auto-accepts via synthetic envelope
- [ ] 1.4 Wire `gate.release()` to trigger queue drain (call `open_fn` for head of queue)
- [ ] 1.5 Add bypass activation notify (`vim.notify WARN` on first `set("bypass")` per session)

## 2. Public API Surface (Lua)

- [ ] 2.1 Add `api.gate()` (cycle: normal→hold→bypass→normal) to `lua/neph/api.lua`
- [ ] 2.2 Add `api.gate_hold()`, `api.gate_bypass()`, `api.gate_release()`, `api.gate_status()` to `lua/neph/api.lua`
- [ ] 2.3 Add `api.tools_status()` (opens NephStatus float) and `api.tools_preview()` to `lua/neph/api.lua`
- [ ] 2.4 Register `:NephInstall [name]` and `:NephInstall --preview` user commands in `lua/neph/init.lua`

## 3. Statusline Integration

- [ ] 3.1 Update `lua/neph/api/status.lua` to include gate state token (`[HELD]` / `[BYPASS]`) when not normal

## 4. Tools Inspector (Lua)

- [ ] 4.1 Add `M.status(root, agents)` to `lua/neph/internal/tools.lua` returning per-agent install state table
- [ ] 4.2 Add `M.preview(root, agents)` to `lua/neph/internal/tools.lua` returning pending changes without side effects
- [ ] 4.3 Create `lua/neph/api/status_buf.lua` (or extend existing status module) to render NephStatus floating buffer with agent table + gate state header
- [ ] 4.4 Add buffer-local keymaps in NephStatus buffer: `i` install, `p` preview, `q` quit

## 5. CLI — Gate Commands

- [ ] 5.1 Add `neph gate` command group to neph-cli TypeScript with subcommands: `hold`, `bypass`, `release`, `status`
- [ ] 5.2 Implement socket resolution (read `$NVIM_SOCKET_PATH`; exit 1 with message if unset/unreachable)
- [ ] 5.3 Implement RPC call wrapper: `nvim --server <socket> --remote-expr "luaeval(...)"` for each gate subcommand
- [ ] 5.4 Add `neph gate --help` with state descriptions

## 6. CLI — Tools Commands

- [ ] 6.1 Add `neph tools` command group with subcommands: `status`, `install [name]`, `uninstall [name]`, `preview [name]`
- [ ] 6.2 Implement `neph tools status` — calls `tools.status()` via RPC; falls back to filesystem-only with `--offline`
- [ ] 6.3 Implement `neph tools install [name]` — runs `tools.install_agent()` via RPC or directly, notifies Neovim on completion
- [ ] 6.4 Implement `neph tools preview [name]` — calls `tools.preview()` via RPC, prints `+`/`-` diff

## 7. User Config Keymaps

- [ ] 7.1 Add `<leader>jg` → `api.gate()` (cycle) keymap to `~/.config/nvim/.../neph.lua`
- [ ] 7.2 Add `<leader>jn` → `api.tools_status()` keymap to `~/.config/nvim/.../neph.lua`

## 8. Tests

- [ ] 8.1 Create `tests/gate_spec.lua` — unit tests for `gate.get/set/release`, state transitions, invalid state error
- [ ] 8.2 Add tests to `tests/review_queue_spec.lua` — hold suppresses open_fn, bypass auto-accepts, release drains queue
- [ ] 8.3 Add tests to `tests/backend_integration_spec.lua` or new spec — `tools.status()` returns correct shape for agents with/without tools
- [ ] 8.4 Add `api.gate()` cycle tests to `tests/setup_smoke_spec.lua` or a new `tests/api_spec.lua`

## 9. Documentation

- [ ] 9.1 Update `README.md`: add "Review Gate" section with keymap table and CLI commands
- [ ] 9.2 Update `README.md`: add "Tools Inspector" section with `:NephStatus` and `neph tools` usage
- [ ] 9.3 Update `doc/neph.txt` (or equivalent vimdoc) with gate API, NephInstall command, and CLI reference
- [ ] 9.4 Add LuaDoc `---@mod` header to `gate.lua` consistent with other internal modules
