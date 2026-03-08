## Tasks

### Task 1: Add random-access methods to review engine session

**Files:** `lua/neph/api/review/engine.lua`, `tests/api/review/engine_spec.lua`

- Add `decisions` array (indexed by hunk number, nil = undecided)
- Add `accept_at(idx)` — sets decisions[idx] to `{decision="accept"}`
- Add `reject_at(idx, reason?)` — sets decisions[idx] to `{decision="reject", reason=reason}`
- Add `get_decision(idx)` — returns decisions[idx] or nil
- Add `is_complete()` — returns true if all decisions are non-nil
- Add `accept_all_remaining()` — accept all nil decisions
- Add `reject_all_remaining(reason?)` — reject all nil decisions
- Keep existing sequential methods (`accept()`, `reject()`, etc.) working by delegating to `accept_at(current_idx)` etc.
- Update `finalize()` to treat nil decisions as reject (safety: undecided = reject)

**Tests:**
- Random-access: accept hunk 3, then hunk 1, verify both recorded
- `is_complete()` with mixed states
- `finalize()` with undecided hunks produces reject decisions
- `accept_all_remaining` skips already-decided hunks
- Backward compat: sequential accept/reject still works

### Task 2: Replace inputlist with buffer-local keymaps in UI

**Files:** `lua/neph/api/review/ui.lua`, `lua/neph/config.lua`

- Remove `start_review` inputlist loop
- Add `find_hunk_at_cursor(hunks, cursor_line)` — returns hunk index nearest to cursor
- Register buffer-local keymaps on left_buf when review starts:
  - `ga` → accept hunk at cursor, update sign, jump to next undecided
  - `gr` → reject hunk at cursor (prompt reason via `vim.fn.input`), update sign, jump to next undecided
  - `gA` → accept all remaining undecided, finalize
  - `gR` → reject all remaining undecided (prompt reason), finalize
  - `q` → reject all undecided with reason "User exited review", finalize
- Add winbar update function: `update_winbar(win, idx, total, decision_text)`
- Update signs on each action (remove old sign, place new sign)
- Position cursor to hunk start_a line on navigation actions
- Auto-finalize when `session.is_complete()` returns true after any action
- Add `review_keymaps` to `neph.Config` defaults

**Tests:**
- `find_hunk_at_cursor` returns correct index for cursor inside hunk, between hunks, before first, after last
- Winbar string format validation
- Keymap config defaults exist

### Task 3: Wire up finalization and cleanup

**Files:** `lua/neph/api/review/ui.lua`, `lua/neph/api/review/init.lua`

- On finalize: clean up keymaps (unmap all), call `on_done(envelope)`, close tab
- On TabClosed (premature close): reject all undecided, finalize
- On `q` keymap: reject all undecided with reason, finalize
- Ensure cleanup removes signs, extmarks, winbar, and keymaps
- Verify atomic result file write still works (init.lua `write_result` unchanged)

**Tests:**
- E2E: open review with known hunks, call session.accept_at/reject_at directly, verify envelope
- Verify TabClosed produces reject envelope for undecided hunks

### Task 4: Update existing tests for new session API

**Files:** `tests/api/review/engine_spec.lua`, `tests/e2e/engine_fuzz_test.lua`

- Update any tests that depend on sequential-only session API
- Add fuzz test cases for random-access patterns
- Verify all existing engine tests still pass with new session internals
