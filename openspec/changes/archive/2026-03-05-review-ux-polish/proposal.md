## Why

The current diff review UI (`open_diff.lua`) lacks visual feedback and discoverability. Users cannot tell which hunk they're on, what keys to press, or whether previous hunks were accepted/rejected. This makes the review process confusing and error-prone.

## What Changes

- Add sign column indicators (✅ accepted, ❌ rejected, 👉 current, 💬❌ has comment) to visually track hunk decisions
- Display terse virtual text hints at current hunk showing available keybindings (`[y]es [n]o [a]ll [d]eny [e]dit [?]help`)
- Show "hunk X/Y" counter as virtual text to indicate position in review
- Add `?` keymap to toggle expanded help text
- Make sign icons configurable via plugin config (allow ASCII fallback for non-emoji terminals)

## Capabilities

### New Capabilities
- `review-visual-feedback`: Sign column indicators and virtual text hints for diff review UX

### Modified Capabilities
- `shim-review-protocol`: Add hunk range tracking and sign/extmark placement to `open_diff.lua`

## Impact

**Affected code:**
- `tools/core/lua/open_diff.lua` — add sign definitions, extmark placement, hunk range tracking, help toggle
- `lua/neph/config.lua` — add `review_signs` config table with customizable icons
- `tools/core/tests/test_shim.py` — add integration tests for sign placement and virtual text
- `tests/` — add Lua plenary tests for sign and extmark behavior (if feasible without live Neovim)

**User-facing:**
- Non-breaking: existing keymaps unchanged, visual feedback is additive
- Config: optional `neph.setup({ review_signs = { accept = "✅", reject = "❌", current = "👉", commented = "💬❌" } })`
