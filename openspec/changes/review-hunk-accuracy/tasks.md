## 1. Engine — Dual-range HunkRange

- [ ] 1.1 Change `HunkRange` type to `{ start_a, end_a, start_b, end_b }` and update `compute_hunks()` to populate both sides from `vim.diff` indices
- [ ] 1.2 Update all engine tests to assert on the new 4-field HunkRange shape

## 2. UI — Correct buffer indexing

- [ ] 2.1 Update `prompt_next()` to use `start_a`/`end_a` for left_buf and `start_b`/`end_b` for right_buf when reading hunk lines
- [ ] 2.2 Update cursor positioning and sign placement to use `start_a` (left_buf stays on old-side coords)
- [ ] 2.3 Update `show_hints()` to place the extmark at `start_b` on right_buf

## 3. Preview — Context and diff coloring

- [ ] 3.1 Build preview lines with 3 lines of context before/after the hunk, clamped to buffer boundaries
- [ ] 3.2 Add `DiffAdd` extmark highlights on changed lines in "Accept" / "Accept all" preview
- [ ] 3.3 Keep "Reject" / "Reject all" preview with syntax-only highlighting (no diff color)

## 4. Verification

- [ ] 4.1 Run full test suite to verify no regressions
