## Why

Three usability issues in the review diff UI:

1. **CURRENT/PROPOSED labels hidden by dropbar**: The labels are in buffer names (`[CURRENT ...] file.ts`) and right-side winbar. Plugins like dropbar override winbar, hiding the labels entirely. Users can't tell which side is which.
2. **No line numbers**: The diff windows don't enable `number`, making it hard to reference specific lines.
3. **`ga` appears to accept all with single-hunk diffs**: When an agent sends full-file content and the diff produces only 1 hunk, `ga` (accept current) and `gA` (accept all) behave identically — accepting the single hunk auto-finalizes. This is technically correct but confusing. The winbar should make it clearer that there's only 1 hunk so the user understands why the review closed immediately.

## What Changes

- **Move CURRENT/PROPOSED labels to window-local virtual text** instead of buffer names and winbar. Use a floating window or `winbar` with explicit `vim.wo` settings that suppress dropbar for review windows.
- **Enable line numbers** (`number = true`) on both diff windows.
- **Remove CURRENT/PROPOSED from buffer names** — use clean names like `neph://review/current/file.ts` and `neph://review/proposed/file.ts`.
- **No behavioral changes** — keymaps, hunk logic, finalization, and envelope generation are unchanged.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `review-ui`: Labels move from buffer names to winbar with dropbar suppression; line numbers enabled in diff windows.

## Impact

- `lua/neph/api/review/ui.lua` — buffer name format, window options, winbar content
- No engine changes. No protocol changes. No test fixture changes.
