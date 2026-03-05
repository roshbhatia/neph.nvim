## Context

`open_diff.lua` currently opens a two-pane diff (left = current, right = proposed) and registers buffer-local keymaps (y/n/a/d/e) for hunk review. It tracks hunk decisions in a Lua table and writes a ReviewEnvelope JSON on finalize. However, there is no visual feedback during the review: users can't see which hunk they're on, what decisions they've made, or what keys to press.

The UI needs minimal polish to make the review process discoverable and transparent without adding heavyweight features like qflist integration or multi-file workflows (those are non-goals for this iteration).

## Goals / Non-Goals

**Goals:**
- Visual feedback: signs in the gutter show hunk status (current/accepted/rejected/commented)
- Discoverability: virtual text hints at the current hunk show available keys
- Configurability: sign icons can be overridden in `neph.setup()` for ASCII-only terminals
- Minimal overhead: no new dependencies, no complex state, no multi-file logic

**Non-Goals:**
- Qflist integration (not needed for single-file review)
- Multi-file review support (future enhancement)
- Floating window help UI (virtual text is sufficient)
- Persistent review state across Neovim restarts

## Decisions

### Decision 1: Signs over highlights for hunk status

**Rationale:** Sign column is persistent and doesn't interfere with syntax highlighting. Using `nvim_buf_set_extmark` with `sign_text` is the modern API (Neovim 0.10+). Alternatives considered:
- Line highlights: too intrusive, obscures code
- Floating windows: heavyweight, requires window management

**Implementation:** Define a sign group `neph_review` with four signs:
- `neph_current` (👉) — placed at the start line of the hunk under review
- `neph_accept` (✅) — replaces `neph_current` after `y` keypress
- `neph_reject` (❌) — replaces `neph_current` after `n` keypress (no reason)
- `neph_commented` (💬❌) — replaces `neph_current` after `n` keypress (with reason)

Signs are placed via `vim.fn.sign_place()` and unplaced via `vim.fn.sign_unplace()` when the hunk index changes.

### Decision 2: Virtual text (extmarks) for hints and hunk counter

**Rationale:** Virtual text is ephemeral, doesn't modify buffer content, and can be cleared/replaced easily. Use two extmarks on the right buffer at the current hunk:
1. `"← hunk X/Y"` at the end of the first line of the hunk (aligned via `virt_text_pos = 'eol'`)
2. `"[y]es [n]o [a]ll [d]eny [e]dit [?]help"` on the next line (terse, single-line, `|` separators)

When `?` is pressed, toggle a boolean and replace line 2 with expanded help: `"y=accept | n=reject+reason | a=accept-all | d=reject-all | e=manual | [?] hide"`.

Extmarks are namespaced under `neph_review_hints` and cleared via `nvim_buf_clear_namespace()` before placing new ones.

### Decision 3: Hunk range tracking via diff metadata

**Rationale:** To place signs and count hunks, we need to know each hunk's `{ start_line, end_line }` in the left buffer. The current implementation uses `]c`/`[c` to navigate but doesn't store ranges.

**Implementation:** After opening the diff, parse the diff metadata from the left buffer's diff filler lines using `vim.diff()` or walk the buffer with `vim.fn.diff_hlID()` to identify hunk boundaries. Store in a module-local table:
```lua
local hunk_ranges = {
  { start_line = 23, end_line = 25 },  -- hunk 1
  { start_line = 45, end_line = 46 },  -- hunk 2
  ...
}
```

Alternative considered: Track cursor position and infer hunk boundaries dynamically. Rejected because it's fragile (what if user manually moves cursor?).

### Decision 4: Config schema for sign icons

**Rationale:** Emoji signs may not render in all terminals. Allow users to override via:
```lua
require("neph").setup({
  review_signs = {
    accept = "✅",
    reject = "❌",
    current = "👉",
    commented = "💬❌",
  }
})
```

Default to emoji, document ASCII alternatives in README (`+`, `-`, `>`, `*`).

**Implementation:** Add `review_signs` table to `lua/neph/config.lua` defaults. Read config in `open_diff.lua` via `vim.g.neph_config` (set by `neph.setup()`). Fallback to emoji if config is absent (backward-compatible).

## Risks / Trade-offs

**Risk:** Hunk range parsing is complex and may fail for edge cases (binary diffs, submodule changes, etc.)
- **Mitigation:** Use `pcall()` around diff parsing; fall back to no signs if it fails. Emit a warning in `:messages`.

**Risk:** Virtual text on the right buffer may be obscured if lines are very long.
- **Mitigation:** Place extmarks on the right buffer at the _first_ line of the hunk (most likely to be visible). Users can scroll horizontally if needed.

**Risk:** Sign column width increases by 1-2 chars if not already visible.
- **Mitigation:** Neovim auto-adjusts sign column width. Document that users can set `signcolumn=yes:1` to reserve space.

**Trade-off:** Help toggle (`?`) replaces the hint line instead of showing a separate floating window.
- **Benefit:** No window management, no z-index issues, immediate visual feedback.
- **Downside:** Less room for expanded help (single line). Mitigate by keeping help terse.

**Trade-off:** Signs are only placed in the left buffer (current), not the right (proposed).
- **Rationale:** The left buffer is where decisions are applied; the right is read-only reference. Placing signs on both would be redundant and visually noisy.
