## Why

The review workflow has several small friction points that accumulate into real daily annoyance: cursor position is lost after every review, the winbar doesn't show which file is being reviewed, rapid agent writes create notification storms, and there's no way to inspect or manage the review queue without being inside an active review. Fixing these now, while the review system is well-tested, costs little and pays back on every review session.

## What Changes

- **Cursor restore**: Save the originating window and cursor position before `tabnew`; restore after review tab closes — no more jumping to line 1 after every approval.
- **File path in winbar**: Add truncated relative path to the review winbar so the user always knows which file they're deciding on.
- **Targeted checktime on accept**: After a pre-write review accept/partial, trigger `checktime` on the reviewed file's buffer immediately rather than waiting for `agent.end`.
- **Debounced batch queue notifications**: Replace per-enqueue popups with a single debounced "N reviews queued (agent)" message; first review (opens immediately) still notifies immediately.
- **Queue inspector UI**: `:NephQueue` command opens a floating window listing pending reviews with file, agent, and position; `dd` cancels, `<CR>` jumps to file, `q` closes.
- **Pre-submit summary**: When `gs` is pressed with 3+ hunks, show a floating summary of all decisions (✓ accepted, ✗ rejected with reasons, ? undecided) before finalizing — confirm with `<CR>` or cancel with `q`.
- **Gate state winbar indicator**: When gate enters `hold` or `bypass` mode, display a persistent indicator in a dedicated neph winbar on the current window; cleared on gate release.

## Capabilities

### New Capabilities

- `review-cursor-restore`: Save and restore the originating cursor position across a review session.
- `review-queue-inspector`: Floating UI for inspecting, navigating, and cancelling pending reviews.
- `review-submit-summary`: Pre-finalization summary popup showing all hunk decisions before `gs` commits.
- `gate-winbar-indicator`: Persistent visual indicator when gate is in hold or bypass mode.

### Modified Capabilities

- `review-ui`: Winbar gains file path display; submit handler gains summary gate; `open_diff_tab` gains cursor save/restore support.
- `review-queue`: Notification debouncing replaces per-enqueue popups.

## Impact

- `lua/neph/api/review/ui.lua` — `open_diff_tab` (cursor save), `build_winbar` (file path), submit handler (summary)
- `lua/neph/api/review/init.lua` — `finish_review` (cursor restore, targeted checktime)
- `lua/neph/internal/review_queue.lua` — debounced notification logic
- `lua/neph/api/review/queue_ui.lua` — new file: queue inspector floating window
- `lua/neph/internal/gate_ui.lua` — new file: gate winbar indicator helper
- `lua/neph/api.lua` — wire gate_ui into gate transition functions
- `lua/neph/init.lua` — register `:NephQueue` command
