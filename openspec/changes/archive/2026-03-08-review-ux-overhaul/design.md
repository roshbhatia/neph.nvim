## Context

The review diff UI (`lua/neph/api/review/ui.lua`) opens a two-pane vimdiff tab for hunk-by-hunk code review. Currently it has several UX problems:

1. **Sign off-by-one**: Signs placed at `h.start_a` appear 1 line below where Neovim renders the diff highlight. The `vim.diff` indices result for pure insertions returns the anchor line, but the visual diff filler appears on the next line.
2. **Left pane line numbers missing**: `vim.wo[left_win].number = true` is set but something resets it (likely `diffthis` or a plugin interaction).
3. **Signs only on left buffer**: No visual feedback on the proposed (right) side about what's being accepted/rejected.
4. **Auto-finalize**: `after_action()` calls `do_finalize()` when `is_complete()` returns true, and `gA`/`gR` finalize immediately. No walkback possible.
5. **No undo**: Once a hunk is decided, the only option is to flip it with the opposite action. No way to return to undecided.

The engine (`engine.lua`) already supports random-access decisions and `accept_all_remaining`/`reject_all_remaining` that skip decided hunks. The UI layer is what needs the overhaul.

## Goals / Non-Goals

**Goals:**
- Signs align with Neovim's diff highlight rendering on both panes
- Both panes show inverse sign indicators (accept = ✓ on proposed, ✗ on current)
- Line numbers reliably appear on both panes
- Developer can freely navigate, decide, flip, undo, and review before explicitly submitting
- `gA`/`gR` only affect undecided hunks and don't finalize
- Winbar shows at-a-glance decision tally

**Non-Goals:**
- Changing the review protocol or envelope schema
- Adding inline editing of hunks (edit-before-accept)
- Custom sign icons beyond the existing configurable set
- Right-pane interactivity (keymaps remain on left buffer only)

## Decisions

### 1. Sign placement: subtract 1 from start line

**Decision**: Place signs at `max(1, h.start_a - 1)` on left and `max(1, h.start_b - 1)` on right.

**Rationale**: `vim.diff` with `result_type = "indices"` returns 1-indexed line numbers where `start_a` is the first changed/deleted line. Neovim's `diffthis` renders the diff highlight starting at that line, but the gutter sign appears to be associated with the line visually — testing shows the sign needs to be 1 line prior to align with where the diff color block begins. The `max(1, ...)` clamp handles hunks that start at line 1.

**Alternative**: Adjust only for pure insertions (`count_a == 0`). Rejected because the user reports the issue is general, not insertion-specific.

### 2. Force line numbers via window options + guard autocmd

**Decision**: Set `number = true` on both windows after `diffthis`, and add a `WinEnter` autocmd scoped to the review tab that re-forces `number = true` on both windows.

**Rationale**: Something resets the left window's number option after initial setup. A guard autocmd ensures it stays set regardless of what plugin or diff sync event clears it. The autocmd is scoped to the tab and cleaned up on review finalize/cleanup.

**Alternative**: Use `vim.api.nvim_set_option_value` with `scope = "local"`. May not survive diff sync either, so the guard autocmd is the belt-and-suspenders approach.

### 3. Dual-side signs with inverse semantics

**Decision**: Place signs on both left and right buffers. The sign reflects what happens to *that side's code*:

| Decision | Left (current) | Right (proposed) |
|---|---|---|
| Accept | `neph_reject` (✗) — replaced | `neph_accept` (✓) — taken |
| Reject (no reason) | `neph_accept` (✓) — kept | `neph_reject` (✗) — discarded |
| Reject (with reason) | `neph_accept` (✓) — kept | `neph_commented` (💬) — feedback |
| Current (undecided) | `neph_current` (→) | `neph_current` (→) |
| Undecided (not current) | no sign | no sign |

**Rationale**: At a glance, scanning either column tells you "what survives." The 💬 sits on the proposed side because that's what the rejection reason comments on.

**Implementation**: Add `right_sign_ids = {}` to `ui_state`. In `refresh_ui()`, mirror sign placement using `h.start_b - 1` on `right_buf`. `sign_place` works on non-modifiable buffers (signs are metadata).

### 4. Remove auto-finalize, add explicit `<CR>` submit

**Decision**:
- Remove `if session.is_complete() then do_finalize()` from `after_action()`
- Remove `do_finalize()` calls from `gA`/`gR` handlers
- Add `<CR>` keymap for explicit submit
- On submit: if all decided, finalize immediately. If undecided hunks remain, prompt via `vim.ui.select` with options: submit (reject undecided), jump to first undecided, or cancel.

**Rationale**: Auto-finalize prevents walkback. The git staging mental model (stage freely, commit explicitly) is what developers expect. The prompt on undecided hunks prevents accidental data loss while keeping the fast path (all decided → instant submit) frictionless.

### 5. `gu` to clear decision back to undecided

**Decision**: Add `clear_at(idx)` to the engine session that sets `decisions_by_idx[idx] = nil`. Wire it to `gu` keymap.

**Rationale**: Flipping accept↔reject via `ga`/`gr` covers most walkback cases, but "I need to think about this more" is a distinct state. Undecided hunks show up in the `?N` tally and get caught by the submit prompt, making them a useful "bookmark for later" mechanism.

### 6. Winbar tally format

**Decision**: Add tally counts to both winbars:
- Left: `CURRENT  Hunk 3/7: accepted  ✓4 ✗2 ?1  ga=accept gr=reject <CR>=submit q=quit`
- Right: `PROPOSED  ✓4 ✗2 ?1`

**Rationale**: Developers need at-a-glance progress without scanning all signs. The tally is cheap to compute (loop over decisions) and provides immediate feedback after `gA`/`gR` bulk actions.

## Risks / Trade-offs

- **[Sign off-by-one might be context-dependent]** → Verify with multiple diff types (insertion, deletion, modification) during implementation. If `-1` is wrong for some cases, we may need per-hunk-type adjustment.
- **[Right buffer sign_place on non-modifiable buf]** → Verify in Neovim 0.10+. If it fails, temporarily set `modifiable = true`, place sign, set back. Low risk.
- **[Removing auto-finalize is a breaking behavior change]** → Users who relied on auto-close will now need to press `<CR>`. This is intentional and better UX, but worth noting in any changelog.
- **[Guard autocmd for line numbers adds complexity]** → Scoped to tab and cleaned up on review close. Minimal footprint.
