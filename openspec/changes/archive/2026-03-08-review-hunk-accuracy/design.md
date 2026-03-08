## Context

The review engine uses `vim.diff(old, new, { result_type = "indices" })` which returns `{start_a, count_a, start_b, count_b}` per hunk. Currently `compute_hunks()` only exposes the old-side (`start_a`/`count_a`) as `HunkRange.start_line`/`end_line`. The UI then incorrectly uses these old-side coordinates to index into the new-side buffer, grabbing wrong lines when hunks change line counts.

## Goals / Non-Goals

**Goals:**
- Hunk cursor/sign/preview aligns with what vimdiff highlights
- Preview shows context lines around the change
- Changed lines in preview have diff-colored highlighting

**Non-Goals:**
- Changing the review envelope format (it stays `review/v1`)
- Changing `apply_decisions()` — it already uses raw `vim.diff` indices directly
- Adding unified diff view in preview (just context + color is enough)

## Decisions

### 1. Dual-range HunkRange
**Choice:** Extend `HunkRange` to carry both sides:
```
{ start_a, end_a, start_b, end_b }
```
**Why:** The UI needs old-side coords for left_buf operations and new-side coords for right_buf operations. Carrying both avoids re-computing the diff in the UI layer.
**Alternative:** Re-run `vim.diff` in the UI — wasteful and duplicates logic.

### 2. Context lines from full buffer
**Choice:** Grab 3 lines before and after the hunk from the respective full buffer. Show them as dimmed/normal text with the hunk lines colored.
**Why:** Matches the familiar `git diff -U3` experience. 3 lines is enough to orient without overwhelming the preview.

### 3. Extmark-based diff coloring in preview
**Choice:** After setting preview lines, add `DiffAdd` highlight extmarks on the changed lines for "Accept" preview, and `DiffDelete` for "Reject" preview (showing what you'd lose).
**Why:** Snacks picker preview supports `ctx.preview:highlight()` for filetype, but we need per-line diff colors on top. Extmarks layer cleanly over syntax highlighting.

### 4. Preview content per action
- **Accept preview:** Context + new lines highlighted with `DiffAdd`
- **Reject preview:** Context + old lines (no special highlight — you're keeping them)
- **Accept all / Reject all:** Same as accept/reject but for current hunk

## Risks / Trade-offs

- **HunkRange shape change breaks tests:** Engine tests assert on `{start_line, end_line}`. Need to update to `{start_a, end_a, start_b, end_b}`. Low risk — test updates are mechanical.
- **Context lines at file boundaries:** Need `math.max(1, ...)` / `math.min(#lines, ...)` clamping. Simple edge case.
