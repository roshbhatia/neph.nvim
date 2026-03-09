## Why

The review diff UI has several UX issues that make hunk-by-hunk code review frustrating: sign markers are placed one line below the actual diff highlight, line numbers don't appear on the left (current) pane, signs only appear on one side of the diff making it hard to see what's being kept vs replaced, and the auto-finalize behavior prevents developers from walking back decisions or reviewing their choices before submitting.

## What Changes

- Fix off-by-one sign placement so markers align with diff highlights (signs currently appear 1 line below)
- Force line numbers on both diff panes (left currently loses them)
- Place signs on both left (current) and right (proposed) buffers with **inverse semantics**: accept shows `✗` on left (replaced) and `✓` on right (taken); reject shows `✓` on left (kept) and `✗`/`💬` on right (discarded)
- **BREAKING**: Remove auto-finalize on last hunk decision — review stays open until explicit `<CR>` submit
- **BREAKING**: `gA`/`gR` no longer auto-finalize — they apply to undecided hunks only, leaving the review open
- Add `gu` keybinding to clear a decision back to undecided (walkback)
- Add `<CR>` keybinding for explicit submit with confirmation prompt when undecided hunks remain
- Add decision tally (`✓N ✗N ?N`) to both winbars for at-a-glance progress

## Capabilities

### New Capabilities

- `review-walkback`: Ability to clear or flip hunk decisions before finalizing, including undo-to-undecided and explicit submit flow
- `review-dual-signs`: Dual-side sign placement with inverse semantics showing accept/reject outcome on both current and proposed buffers

### Modified Capabilities

- `review-ui`: Sign placement fix, forced line numbers, removal of auto-finalize, gA/gR no longer finalize, winbar tally display

## Impact

- `lua/neph/api/review/ui.lua` — sign placement, dual-buffer signs, new keymaps, winbar format, submit flow, removal of auto-finalize
- `lua/neph/api/review/engine.lua` — possible `clear_at(idx)` method for undo-to-undecided
- `lua/neph/config.lua` — new keymap defaults (`gu`, `<CR>` submit)
- `tests/api/review/ui_spec.lua` — updated tests for new sign logic, winbar format
- `tests/api/review/engine_spec.lua` — tests for clear_at, tally helpers
- Existing `review_keymaps` config key gains new entries (backward compatible — new keys have defaults)
