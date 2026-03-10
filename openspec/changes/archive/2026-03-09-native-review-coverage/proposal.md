## Why

Every agent file write should go through the hunk-based review UI, but today only hook agents (Claude, Copilot) and extension agents with custom tool overrides (Pi, Amp, OpenCode) trigger review. Terminal agents (Goose, Codex, Crush) write directly to disk with zero interception. Gemini's companion sidecar only pushes context — it has no write tool interception. Cursor is post-write only (no review, just checktime). This means 4 out of 10 agents bypass the review UI entirely, and there's no safety net if an extension's tool override fails to trigger. The user has no way to accept, reject, or partially apply file changes from these agents.

## What Changes

- **Filesystem watcher for post-write review**: A project-level `vim.uv.new_fs_event` watcher that detects file changes while any agent is active. When a file changes on disk and the change didn't come from the review UI itself, show a post-write review diff so the user can see what changed (and optionally revert).
- **Gemini write tool interception**: Add write/edit tool interception to the Gemini integration (companion sidecar or dedicated tool handler) so Gemini file writes go through `NephClient.review()` like Pi, Amp, and OpenCode.
- **Visual feedback during gate block**: When the neph-cli gate is blocking (waiting for review decision), show a notification/spinner in Neovim so the user knows a review is pending and which file needs attention.
- **Concurrent review queue**: When an agent writes multiple files rapidly, queue review requests and present them sequentially rather than losing or racing reviews. Show a count of pending reviews.
- **Post-write review for Cursor**: Since Cursor fires hooks after writing, use the same filesystem watcher mechanism to show what Cursor changed (replacing the current checktime-only flow).

## Capabilities

### New Capabilities
- `fs-watcher-review`: Project-level filesystem watcher that detects agent file writes and triggers post-write review diffs when changes bypass the pre-write review path
- `review-queue`: Sequential queue for concurrent review requests with pending count display, preventing lost reviews when agents write multiple files rapidly
- `review-pending-feedback`: Visual notification in Neovim when a review is pending (gate blocking), showing which file awaits user decision

### Modified Capabilities
- `gemini-companion-server`: Add write/edit tool interception so Gemini file mutations route through NephClient.review()
- `review-protocol`: Add post-write review mode (file already on disk, show diff against buffer, allow revert) alongside existing pre-write review mode
- `review-ui`: Support review-pending indicator and queued review count in winbar/statusline

## Impact

- **New files**: `lua/neph/internal/fs_watcher.lua` (filesystem watcher), `lua/neph/internal/review_queue.lua` (concurrent review queue)
- **Modified Lua**: `session.lua` (start/stop watcher with agent lifecycle), `review/init.lua` (queue integration, post-write mode), `review/ui.lua` (pending indicator), companion sidecar context
- **Modified TS**: `tools/gemini/src/companion.ts` (tool interception), `tools/neph-cli/src/gate.ts` (pending notification RPC)
- **New RPC methods**: `review.pending` (notify Neovim a review is waiting), `review.queue_status` (pending count)
- **Dependencies**: No new dependencies. Uses `vim.uv.new_fs_event` (built into Neovim >= 0.10)
- **Config**: New optional `review.fs_watcher` config (enable/disable, ignore patterns for node_modules/.git/etc)
