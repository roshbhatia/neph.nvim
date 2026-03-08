## Why

The current review UI uses `vim.fn.inputlist()` to prompt for each hunk decision. This blocks Neovim's event loop, prevents navigating between hunks, and feels like a modal dialog instead of a native Vim workflow. Users can't go back to reconsider a previous hunk, can't freely explore the diff, and can't see the full picture before deciding.

Every native Vim diff workflow uses `]c`/`[c` to jump between changes and keymaps to act. The review should work the same way.

## What Changes

- Replace `inputlist` sequential prompts with buffer-local keymaps in the vimdiff tab
- Add `]c`/`[c` navigation between hunks (uses Vim's native diff navigation)
- Add `ga` (accept), `gr` (reject), `gA` (accept all remaining), `gR` (reject all remaining) keymaps
- Show current hunk status in winbar: `[Hunk 2/5: undecided]`
- Signs update in real-time as user navigates and decides
- Auto-finalize when all hunks are decided
- Escape/`:q` rejects all undecided hunks (preserves the "blocking gate" safety)

## Capabilities

### Modified Capabilities
- `review-ui`: Hunk-by-hunk review with free navigation instead of sequential prompts

## Impact

- **ui.lua**: Rewrite `start_review()` — replace inputlist loop with keymap registration + state tracking
- **ui.lua**: Add winbar update function, hunk cursor positioning
- **engine.lua**: Session needs `accept_at(idx)`/`reject_at(idx)` for random-access decisions (currently only sequential)
- **init.lua**: Minor — `start_review` callback interface unchanged
- **config.lua**: Add `review_keymaps` config option (with defaults)
- **Tests**: New tests for keymap-based review flow, random-access session decisions
- **No CLI changes**: ReviewEnvelope format unchanged, gate exit codes unchanged
