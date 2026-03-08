## Tasks

### Task 1: Remove history.lua and related code

**Files:** `lua/neph/internal/history.lua` (delete), `lua/neph/api.lua`, `lua/neph/init.lua`

- Delete `lua/neph/internal/history.lua`
- Remove `M.history()` from `api.lua`
- Remove `require("neph.internal.history")` from `api.lua`
- Remove any `history.save()` calls (check `input.lua` and `session.lua`)
- Remove history keymap from `init.lua` if present (e.g. `<leader>jh`)
- Verify `M.resend()` in `api.lua` only depends on `terminal.lua` (it should already)

### Task 2: Replace history tests with terminal tests

**Files:** `tests/history_spec.lua` (delete), `tests/terminal_spec.lua` (create)

- Delete `tests/history_spec.lua`
- Create `tests/terminal_spec.lua`:
  - `set_last_prompt` + `get_last_prompt` round-trip
  - `get_last_prompt` returns nil for unknown termname
  - Multiple agents maintain separate last prompts
  - Setting new prompt overwrites previous

### Task 3: Verify no broken references

- Run `task test` — all tests pass
- Run `task lint` — no warnings
- Grep for "history" in lua/neph/ to confirm no remaining references
