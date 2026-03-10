## Context

neph.nvim intercepts agent file writes via two mechanisms: **gate hooks** (Claude, Copilot, Cursor via neph-cli stdin parsing) and **extension tool overrides** (Pi, Amp, OpenCode, Gemini via NephClient.review()). Both converge on the Lua `review.open()` which shows an interactive vimdiff UI for hunk-by-hunk accept/reject.

Current coverage gaps:
- **Terminal agents** (Goose, Codex, Crush) write directly to disk — no interception mechanism exists
- **Cursor** is post-write only (gate does checktime, no review)
- **Gemini** has `openDiff` MCP tool via companion, but if Gemini writes files through a path that doesn't call `openDiff`, those writes are unreviewed
- No safety net if any agent's tool override fails to trigger
- When an agent writes multiple files rapidly, reviews can race or get lost
- No visual feedback to the user when a gate hook is blocking and waiting for review

## Goals / Non-Goals

**Goals:**
- Every agent file write produces a review diff, even if the write already happened (post-write review)
- Filesystem watcher as a universal safety net — catches writes that bypass tool overrides
- Sequential review queue so rapid multi-file writes don't race
- Visual notification when review is pending
- Works with both WezTerm and snacks backends

**Non-Goals:**
- Blocking writes before they hit disk for terminal agents (impossible without hook support)
- Real-time collaborative editing (this is review, not co-editing)
- Replacing the existing pre-write review flow (fs-watcher is additive, not a replacement)
- Supporting agents that don't run through neph's session management

## Decisions

### Decision 1: `vim.uv.new_fs_event` per-file watcher (not recursive directory watcher)

**Choice**: Watch individual open buffers + recently-touched project files, not the entire project tree.

**Rationale**: `vim.uv.new_fs_event` (libuv's `uv_fs_event_t`) uses inotify on Linux and FSEvents on macOS. Recursive directory watching on large projects (node_modules, .git) would exhaust inotify limits and waste resources. Instead:
1. Watch files that are currently open in Neovim buffers
2. Watch files the agent has previously touched in this session (tracked via review history)
3. Stop watching when no agent is active (`vim.g.{name}_active` is nil for all agents)

**Alternative considered**: Project-wide recursive `fs.watch` in the neph-cli Node process. Rejected because it duplicates the Lua-side buffer awareness and adds Node ↔ Neovim round-trips for every change event.

### Decision 2: Post-write review shows "what changed" diff, not a blocking gate

**Choice**: When the fs-watcher detects a file changed on disk and an agent is active, show a non-blocking notification with the option to open a review diff. The diff compares the buffer contents (before) vs the file on disk (after).

**Rationale**: Terminal agents write directly — we can't block them. Making the post-write review non-blocking means it doesn't interfere with the agent's workflow. The user can:
- View the diff (opens review UI with the same hunk-based flow)
- Accept (buffer updates to match disk — equivalent to `:checktime` for that file)
- Reject (revert the file on disk to match the buffer contents)
- Ignore (dismiss notification, file stays changed on disk)

This reuses the existing review engine with a different trigger source.

### Decision 3: Review queue lives in Lua (not neph-cli)

**Choice**: `lua/neph/internal/review_queue.lua` manages a FIFO queue of pending review requests. When a review.open arrives while another review is active, it's queued. When the active review completes, the next one auto-opens.

**Rationale**: The review UI is Lua-side (vimdiff tabs). The queue must be Lua-side to coordinate tab lifecycle. The neph-cli gate already blocks on its own (waiting for the result file), so it naturally serializes — but multiple gates from the same agent (or different agents) could arrive simultaneously. The Lua queue prevents lost reviews.

Queue behavior:
- `review_queue.enqueue(params)` — adds to FIFO, opens immediately if no active review
- `review_queue.on_complete(request_id)` — pops next from queue, opens it
- `review_queue.count()` — number of pending reviews (for statusline)
- Active review + pending count shown in winbar: "Review 1/3"

**Alternative considered**: Queue in neph-cli (Node side). Rejected because multiple independent gate processes can't share state without IPC, and extension agents (Pi, Amp) bypass the CLI entirely.

### Decision 4: Pending review notification via RPC + vim.notify

**Choice**: When neph-cli gate starts blocking for review, it sends an RPC call `review.pending` with the file path. Lua shows a `vim.notify` message: "Review pending: path/to/file.lua". When the review UI opens, the notification is dismissed.

**Rationale**: The user needs to know they should switch to Neovim and act on the review. Without this, the agent terminal just hangs silently. `vim.notify` integrates with existing notification plugins (nvim-notify, fidget.nvim, snacks.notifier) and requires no new UI code.

### Decision 5: Gemini coverage via existing openDiff — no new tool needed

**Choice**: Gemini's companion already routes file writes through `openDiff` → `NephClient.review()`. No additional tool interception is needed. The fs-watcher serves as the safety net if any writes bypass the MCP tool.

**Rationale**: The diff bridge in `tools/gemini/src/diff_bridge.ts` already calls `neph.review()` for file changes. Adding a separate write tool would duplicate this. The fs-watcher catches any edge cases where Gemini writes without calling openDiff.

### Decision 6: Config structure

```lua
-- In neph.Config
review = {
  fs_watcher = {
    enable = true,  -- default: true when any agent is active
    ignore = { "node_modules", ".git", "dist", "build", "__pycache__" },
  },
  queue = {
    enable = true,  -- default: true
  },
  pending_notify = true,  -- default: true
}
```

All features opt-out (enabled by default) to maximize coverage without requiring config changes.

## Risks / Trade-offs

- **[Performance] fs-watcher on many open buffers** → Mitigation: Only watch buffers in the current project root. Cap at 100 watched files. Use debounce (200ms) to batch rapid changes.
- **[False positives] fs-watcher triggers on non-agent writes** → Mitigation: Only trigger post-write review when at least one agent is active (`vim.g.{name}_active`). User saves via `:w` don't trigger because the buffer and disk are already in sync.
- **[UX] Notification fatigue from post-write reviews** → Mitigation: Notification is dismissible. Post-write review is opt-in to open (notification only, not auto-opening the diff). Pre-write review (gate/extension) still auto-opens.
- **[Race condition] File changes during active review** → Mitigation: Ignore fs-watcher events for files currently in review. Queue handles sequential ordering for pre-write reviews.
- **[inotify limits] Linux inotify watch limit** → Mitigation: Per-file watching (not recursive). Default limit is 8192 on most systems. We watch at most ~100 files. Well within limits.
