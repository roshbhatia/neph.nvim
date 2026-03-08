## Why

The review hunk-by-hunk UI has two bugs. First, `compute_hunks()` returns only old-side line ranges (`start_a`/`count_a`) but the UI uses them to index into both the old and new buffers — when hunks add or remove lines, the preview and cursor position grab the wrong lines from the proposed buffer. Second, the picker preview shows only the bare hunk lines with syntax highlighting but no surrounding context and no diff coloring (green/red), making it hard to understand what's changing.

## What Changes

- `compute_hunks()` returns both old-side and new-side ranges per hunk (`start_a`/`end_a` + `start_b`/`end_b`)
- UI indexes left_buf with old-side range and right_buf with new-side range
- Preview shows N lines of context around the hunk (like `git diff -U3`)
- Changed lines in the preview are highlighted with `DiffAdd`/`DiffDelete` colors

## Capabilities

### New Capabilities
- `review-preview-context`: Context lines and diff coloring in the review picker preview

### Modified Capabilities
- `review-protocol`: Hunk ranges include both old-side and new-side coordinates

## Impact

- **engine.lua**: `HunkRange` type gains `start_b`/`end_b` fields; `compute_hunks()` return shape changes
- **ui.lua**: `prompt_next()` uses correct range per buffer; preview callback adds context + extmark highlights
- **engine tests**: Need updating for new HunkRange shape
- **No API changes**: Review envelope format unchanged, accept/reject behavior unchanged
