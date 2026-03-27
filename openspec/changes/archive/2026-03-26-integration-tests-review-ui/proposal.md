## Why

The review flow has a class of bugs — like the "empty vimdiff tab" caused by `nvim_get_current_buf()` returning stale state in an RPC context — that the existing test suite cannot catch because `open_diff_tab` is always stubbed away. Every layer of the review pipeline is unit-tested in isolation, but the seams between them (queue dispatch → `_open_immediate` → real `tabnew` + buffer setup) are invisible to CI. We need integration-level tests that run real Neovim vim commands so regressions in the tab/buffer setup surface before they reach users.

## What Changes

- **New**: `tests/api/review/ui_integration_spec.lua` — integration tests for `open_diff_tab` that exercise actual `vim.cmd("tabnew")`, `nvim_buf_set_lines`, and `diffthis` rather than stubbing them
- **New**: `tests/review_flow_integration_spec.lua` — end-to-end tests wiring the real `review/init.lua` → `review_queue` → `_open_immediate` → `open_diff_tab` chain with minimal stubs (no UI stub)
- **New**: `TESTING.md` — documents the two-tier test strategy: when to unit-test with stubs vs when to write integration tests that use real Neovim APIs

## Capabilities

### New Capabilities

- `review-ui-integration-tests`: Integration tests that call `open_diff_tab` without stubs, verifying the vimdiff tab is created with correct buffer contents, filetype, and diff state in both pre-write and post-write modes.
- `review-flow-integration-tests`: Integration tests for the full `_open_immediate` path — wires real queue + real `_open_immediate` + real `open_diff_tab`, stubs only the engine session (to control hunk count) and write_result (to capture output). Covers: pre-write, post-write, no-changes early exit, noop provider auto-accept, and queue drain.
- `testing-strategy-docs`: A `TESTING.md` that maps the codebase to test tiers (unit / integration / manual) so contributors know where to add tests and understand what each tier can and cannot catch.

### Modified Capabilities

- `review-ui`: Add scenarios for the vimdiff tab buffer setup invariants (buffer must be non-empty after `open_diff_tab`, both windows must exist, diff must be active). These are new requirements the existing spec doesn't cover.

## Impact

- `tests/` — two new spec files; no changes to production `lua/` code
- `TESTING.md` — new documentation file at repo root
- `openspec/specs/review-ui/spec.md` — delta spec adding tab/buffer invariant requirements
- No runtime behaviour changes; pure test coverage improvement
