## Context

The neph.nvim review pipeline has two categories of tests today:

- **Unit tests** (well-covered): each module tested in isolation with heavy stubbing. `open_diff_tab` is always replaced with `function() return { tab = 999 } end`. This means no test ever calls `vim.cmd("tabnew")`, `nvim_buf_set_lines`, or `diffthis`.
- **Integration tests** (none for review UI): the path from `_open_immediate` through real Neovim buffer APIs has zero test coverage.

The "empty vimdiff tab" bug (fixed in commit 60d6f53) was invisible to CI because the stub bypassed the exact code that was broken. We need a test tier that exercises real Neovim commands.

## Goals / Non-Goals

**Goals:**
- Tests that call `open_diff_tab` with no stub and assert the resulting tab/buffers have correct content
- Tests that wire `_open_immediate` → real `open_diff_tab` end-to-end (stub only engine session to control hunk count, and `write_result` to capture output)
- A `TESTING.md` that documents when each test tier applies so contributors know where new tests belong
- A delta spec in `openspec/specs/review-ui/` capturing the buffer/tab invariants as formal requirements

**Non-Goals:**
- Full RPC socket integration tests (those require a live Neovim server process; out of scope here)
- Testing the amp TypeScript plugin or neph CLI
- Changing any production code

## Decisions

### Decision: Run integration tests in the same headless Neovim harness

The existing `nvim --headless -u tests/minimal_init.lua` runner already supports real vim API calls — it's just that all current review tests stub them away. New integration spec files drop the stubs for `open_diff_tab` and run in the same runner. No new tooling needed.

### Decision: Stub only the engine session and write_result, not the UI

Integration tests for `_open_immediate` should stub:
- `engine.create_session` — to return a session with a controlled hunk count (1 or 2 hunks) without needing real diff computation against temp files
- `write_result` capture — to assert the output envelope without file I/O side effects

They should NOT stub `ui.open_diff_tab`. The whole point is to verify the real vim commands run.

For `open_diff_tab` unit tests, no stubs at all — pass real `old_lines`/`new_lines` arrays and assert directly on `vim.api.nvim_buf_get_lines`.

### Decision: Teardown tabs after each integration test

Each test that opens a tab must close it in `after_each`. Use `pcall(vim.cmd, "tabclose " .. tab_nr)` to avoid cascading failures.

### Decision: TESTING.md lives at repo root, not in docs/

Keep it discoverable alongside `README.md`. It should be a concise decision matrix, not a tutorial.

### Decision: delta spec goes in `openspec/specs/review-ui/`

The buffer/tab invariants (`open_diff_tab` must produce non-empty buffers with diff active) are requirements on the review UI capability. They belong as an ADDED requirements section in the existing `review-ui` spec rather than a new capability spec.

## Risks / Trade-offs

- **Headless vim commands are slower**: Integration tests that open real tabs will be ~10-50ms each vs <1ms for unit tests. With 5-10 integration tests this is negligible.
- **Diff state is hard to assert directly**: `diffthis` sets internal diff state that isn't easily readable via API. Proxy assertion: check that both windows exist in the tab and both buffers have the expected line counts. A separate assertion that `diff_hlID` or `vim.fn.diff_filler` behaves as expected is optional.
- **Tab leakage on test failure**: If a test fails before `after_each` closes the tab, subsequent tests may see unexpected tab counts. Mitigate by always using `after_each` cleanup and `pcall` for the close.
