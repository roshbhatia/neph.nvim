## Why

Users currently have no way to manually trigger a code review from within Neovim. Reviews are only initiated by agents (via RPC) or automatically by the filesystem watcher. When an agent modifies a file and the user wants to review changes on their own terms — or when the fs_watcher is disabled — there's no manual entry point. This was identified as a gap when `:NephReviewPost` was referenced in notifications but never implemented.

## What Changes

- Add `:NephReview [file]` command that opens an interactive hunk-by-hunk review of buffer vs disk changes
- Defaults to current buffer's file when no argument is given
- Integrates with the existing review queue (queued if another review is active)
- No result_path or channel_id needed — manual reviews don't notify external agents
- On completion, accepted hunks update the buffer to match disk; rejected hunks keep buffer content (same as existing post-write behavior)
- Add `review()` function to the public API (`neph.api`) for programmatic access

## Capabilities

### New Capabilities

- `manual-review-command`: The `:NephReview` user command and public API for triggering reviews without agent involvement

### Modified Capabilities

- `review-ui`: Accept manual-mode reviews where no external agent is waiting for a result

## Impact

- **Lua**: `lua/neph/init.lua` (command registration), `lua/neph/api.lua` (public API), `lua/neph/api/review/init.lua` (handle manual mode)
- **Tests**: New tests for manual review command validation and queue integration
