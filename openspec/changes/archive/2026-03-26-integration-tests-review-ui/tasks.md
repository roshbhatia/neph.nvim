## 1. open_diff_tab Integration Tests

- [x] 1.1 Create `tests/api/review/ui_integration_spec.lua` with describe block and after_each tab teardown helper
- [x] 1.2 Add test: pre-write mode left buffer contains old_lines (assert via nvim_buf_get_lines)
- [x] 1.3 Add test: pre-write mode right buffer contains new_lines
- [x] 1.4 Add test: left buffer name matches `neph://current/<basename>`
- [x] 1.5 Add test: right buffer name matches `neph://proposed/<basename>`
- [x] 1.6 Add test: post-write mode buffer names are `neph://buffer-before/` and `neph://disk-after/`
- [x] 1.7 Add test: ui_state.left_buf equals nvim_win_get_buf(ui_state.left_win) (the RPC-context invariant)
- [x] 1.8 Add test: ui_state.right_buf equals nvim_win_get_buf(ui_state.right_win)
- [x] 1.9 Add test: both windows appear in nvim_tabpage_list_wins(ui_state.tab)
- [x] 1.10 Add test: ui.cleanup() closes the tab (nvim_tabpage_is_valid returns false after cleanup)

## 2. _open_immediate Flow Integration Tests

- [x] 2.1 Create `tests/api/review/flow_integration_spec.lua` with module reset, engine stub, and tab teardown helpers
- [x] 2.2 Add test: pre-write mode with differing content returns `{ ok=true, msg="Review started" }` and opens a tab
- [x] 2.3 Add test: no-changes (0-hunk engine stub) returns `{ ok=true, msg="No changes" }` and does not open a tab
- [x] 2.4 Add test: no-changes path calls review_queue.on_complete with the request_id
- [x] 2.5 Add test: noop provider (is_enabled_for=false, queue disabled) returns `{ ok=true, msg="Review skipped (noop)" }` without opening a tab
- [x] 2.6 Add test: noop provider calls review_queue.on_complete
- [x] 2.7 Add test: post-write mode with buffer ≠ disk opens a tab and active_review.mode == "post_write"
- [x] 2.8 Add test: queue drain — enqueue two reviews, call on_complete for first, verify second review becomes active

## 3. TESTING.md

- [x] 3.1 Create `TESTING.md` at repo root with two-tier strategy overview (unit vs integration)
- [x] 3.2 Add module-to-tier mapping table covering: review_queue, gate, review_provider, integration, engine, ui (open_diff_tab), _open_immediate, RPC dispatch
- [x] 3.3 Add section explaining what each tier stubs vs exercises for real
- [x] 3.4 Add section: "When to write an integration test" — include the RPC-context empty-tab class of bugs as a concrete example
- [x] 3.5 Add section: required after_each teardown pattern for tests that open tabs
- [x] 3.6 Add section: running tests locally (`nvim --headless -u tests/minimal_init.lua ...`)

## 4. Delta Spec — review-ui

- [x] 4.1 Verify `openspec/changes/integration-tests-review-ui/specs/review-ui/spec.md` is complete (already created as part of proposal phase)

## 5. Validation

- [x] 5.1 Run full test suite and confirm zero failures (`nvim --headless -u tests/minimal_init.lua ...`)
- [x] 5.2 Run stylua check on lua/ and tests/ (`stylua --check lua/ tests/`)
- [x] 5.3 Confirm new integration spec files are picked up by the test runner (check output for new test names)
