## Tasks

- [x] **Task 1: Add neph_connected to gate.ts** — Set `vim.g.neph_connected` via `status.set` at start of `runGate()`, unset in `cleanup()`, handle cursor post-write path, skip when transport is null
- [x] **Task 2: Add neph_connected to review command (index.ts)** — Set `neph_connected` after transport connection in review handler, unset in cleanup
- [x] **Task 3: Add tests** — Verify `neph_connected` set/unset in gate.test.ts and commands.test.ts for gate flow, cursor path, null transport, and review command
- [x] **Task 4: Run full test suite** — `task test` and `task tools:test` all pass
