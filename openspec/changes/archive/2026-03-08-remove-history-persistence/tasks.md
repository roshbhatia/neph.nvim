## Tasks

- [x] **Task 1: Remove history.lua and related code** — Delete `lua/neph/internal/history.lua`, remove `M.history()` from `api.lua`, remove `require("neph.internal.history")`, remove any `history.save()` calls, remove history keymap from `init.lua` if present, verify `M.resend()` only depends on `terminal.lua`
- [x] **Task 2: Replace history tests with terminal tests** — Delete `tests/history_spec.lua`, create `tests/terminal_spec.lua` with round-trip, nil-for-unknown, multi-agent, and overwrite tests
- [x] **Task 3: Verify no broken references** — Run `task test`, run `task lint`, grep for "history" in `lua/neph/` to confirm no remaining references
