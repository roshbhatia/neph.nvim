## 1. Configuration

- [x] 1.1 Add `review` config section to `lua/neph/config.lua` with `fs_watcher` (enable, ignore), `queue` (enable), and `pending_notify` fields, all defaulting to enabled
- [x] 1.2 Add EmmyLua type annotations for the new config fields

## 2. Review Queue

- [x] 2.1 Create `lua/neph/internal/review_queue.lua` with FIFO queue: `enqueue(params)`, `on_complete(request_id)`, `count()`, `get_active()`, `clear_agent(name)`
- [x] 2.2 Wire `review/init.lua` to route `review.open()` through the queue instead of opening directly — if a review is active, queue it; on completion, pop next
- [x] 2.3 Add `agent` field to review params so the queue can track which agent owns each review
- [x] 2.4 Wire `session.kill_session()` to call `review_queue.clear_agent(name)` and cancel the active review if it belongs to the killed agent
- [x] 2.5 Update review UI winbar to show queue position ("Review 1/3") when reviews are queued, sourced from `review_queue.count()`
- [x] 2.6 Write tests for review_queue module: enqueue/dequeue ordering, count, clear_agent, concurrent enqueue behavior

## 3. Post-Write Review Mode

- [x] 3.1 Add `mode` parameter to `review.open()` params — `"pre_write"` (default) or `"post_write"`
- [x] 3.2 In post-write mode, `review/init.lua` reads left from buffer contents and right from disk file, instead of left from disk and right from proposed content
- [x] 3.3 In post-write accept: update the buffer to match disk (`:edit` or `nvim_buf_set_lines`). In post-write reject: write buffer contents to disk. In partial: compute merged content, write to disk, update buffer
- [x] 3.4 Update review UI winbar labels — "Post-write Review" with "Buffer (before)" / "Disk (after)" for post-write mode
- [x] 3.5 Write tests for post-write mode: accept updates buffer, reject writes buffer to disk, partial merges correctly

## 4. Filesystem Watcher

- [x] 4.1 Create `lua/neph/internal/fs_watcher.lua` module with `start()`, `stop()`, `watch_file(path)`, `unwatch_file(path)`, `is_active()` functions
- [x] 4.2 Implement per-file watching using `vim.uv.new_fs_event` with 200ms debounce timer per file
- [x] 4.3 On change detected: compare buffer contents vs disk contents. If they differ and any `vim.g.{name}_active` is set, show notification via `vim.notify`
- [x] 4.4 Add ignore pattern matching against `config.review.fs_watcher.ignore` list
- [x] 4.5 Cap watched files at 100 with debug log when limit reached
- [x] 4.6 Track files currently in review (from review_queue) and skip fs-watcher notifications for them
- [x] 4.7 Wire `session.open()` to start the fs_watcher when the first agent activates, and `session.kill_session()` to stop it when the last agent deactivates
- [x] 4.8 Auto-watch files from open buffers within project root (hook `BufEnter` to add watches, `BufDelete`/`BufWipeout` to remove)
- [x] 4.9 Auto-watch files that complete review (add to watch list on review completion)
- [x] 4.10 Add notification action to open post-write review for the changed file — enqueue a post-write review via `review_queue.enqueue({ mode = "post_write", ... })`
- [x] 4.11 Write tests for fs_watcher: watch/unwatch lifecycle, ignore patterns, cap limit, agent-active gating

## 5. Pending Review Notification

- [x] 5.1 Add `review.pending` RPC method to `lua/neph/rpc.lua` dispatch table
- [x] 5.2 Implement `review.pending` handler in `lua/neph/api/review/init.lua` — compute relative path, call `vim.notify` at INFO level
- [x] 5.3 In neph-cli `gate.ts`, call `review.pending` RPC with `{ path, agent }` immediately before calling `review.open`, so the user sees notification while the review UI loads
- [x] 5.4 Show "Review queued" notification when `review_queue.enqueue()` adds to a non-empty queue (with pending count)
- [x] 5.5 Respect `config.review.pending_notify` — skip notifications when false
- [x] 5.6 Write test for review.pending RPC handler

## 6. Gemini Safety Net

- [x] 6.1 Verify Gemini's `openDiff` MCP tool routes through `NephClient.review()` for all write operations — read `tools/gemini/src/diff_bridge.ts` and confirm coverage
- [x] 6.2 Ensure fs_watcher is active when Gemini agent is running, catching any writes that bypass `openDiff`
- [x] 6.3 Write integration note in Gemini agent definition confirming review coverage via openDiff + fs_watcher safety net

## 7. Integration and Cleanup

- [x] 7.1 Wire fs_watcher setup into `lua/neph/init.lua` setup chain (after session.setup)
- [x] 7.2 Ensure `VimLeavePre` cleanup stops all fs_watcher watches
- [x] 7.3 Run full test suite and fix any regressions from review queue and post-write mode changes
- [x] 7.4 Update contracts.lua if any new config fields need validation
