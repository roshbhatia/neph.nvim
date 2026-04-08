## Context

The review system (`lua/neph/api/review/`) is well-tested and stable after several audit rounds. This change makes purely additive or locally-scoped edits — no new external dependencies, no protocol changes, no breaking API changes. Each improvement is independent and can be implemented and tested in isolation.

Key existing patterns to follow:
- Floating windows use `vim.api.nvim_open_win` with `relative="editor"`, `style="minimal"`, `border="rounded"` — match this style for queue inspector and submit summary.
- Buffer-local keymaps on `nofile` buffers follow the `vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })` pattern.
- All vim API calls that touch windows/buffers from deferred contexts use `vim.schedule`.
- Notifications use `vim.notify(msg, vim.log.levels.INFO/WARN/ERROR)`.

## Goals / Non-Goals

**Goals:**
- Restore cursor position after review tab closes (no state lost)
- Show reviewed file path in the review winbar at all times
- Eliminate notification spam on rapid multi-file agent writes
- Give users visibility into the review queue without being inside a review
- Show a decision summary before finalizing a large review
- Make gate hold/bypass impossible to miss without requiring a custom statusline

**Non-Goals:**
- Multi-level undo for hunk decisions
- Scroll synchronization (vimdiff handles this natively)
- Persistent queue storage across sessions
- Any changes to the RPC/CLI protocol
- Breaking changes to `neph.Config` (all new keys are optional)

## Decisions

### 1. Cursor restore — store on ui_state, restore in finish_review

`open_diff_tab` saves `{ win = vim.api.nvim_get_current_win(), cursor = vim.api.nvim_win_get_cursor(0) }` into `ui_state.originating` before the `tabnew`. `finish_review` in `init.lua` calls `vim.schedule(function() pcall(vim.api.nvim_set_current_win, ...) ; pcall(vim.api.nvim_win_set_cursor, ...) end)` after cleanup. `pcall` guards both because the originating window may have closed.

Chosen over alternatives:
- *Store in init.lua*: Would require threading cursor state through params — noisier.
- *BufEnter autocmd*: Too broad, would fight user navigation during the review.

### 2. File path in winbar — pass `file_path` to `build_winbar`

`build_winbar` gains a `file_path` parameter. It calls `vim.fn.fnamemodify(file_path, ":.")` for a relative path, then truncates to 35 chars with a leading `…` if longer. `refresh_ui` already has access to `ui_state` which carries the file path — thread it through.

### 3. Targeted checktime — `vim.schedule` after `finish_review`

In `finish_review`, after `review_queue.on_complete`, add:
```lua
vim.schedule(function()
  local bufnr = vim.fn.bufnr(file_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("checktime") end)
  end
end)
```
Only triggers for accepted/partial pre-write reviews (where the agent is about to write). Reject path skips this since file won't change.

### 4. Debounced notifications — timer local to review_queue module

Add module-level state: `local notify_timer = nil` and `local pending_notify_batch = {}`. On each enqueue (when `active ~= nil`, i.e. not the first-opens-immediately case), accumulate the request into `pending_notify_batch` and (re)start a 400ms `vim.defer_fn` timer. On fire, emit one message: `"N reviews queued (agent1, agent2)"` grouping by agent. The first review that opens immediately keeps its existing immediate notification path. Timer is cancelled and reset on `M._reset()`.

### 5. Queue inspector — `lua/neph/api/review/queue_ui.lua`

New module, ~80 lines. `M.open()` renders a scratch buffer in a centered floating window. Content is built from `review_queue.get_queue()` (new accessor, returns `queue` table copy) and `review_queue.get_active()`. Layout:

```
┌─ Neph Review Queue ─────────────────────────────┐
│  ● ACTIVE  src/foo.lua               (amp)       │
│  1  src/bar.ts                       (amp)       │
│  2  lib/utils.py                     (amp)       │
│  3  README.md                        (claude)    │
│                                                  │
│  dd=cancel  <CR>=jump  r=refresh  q=close        │
└──────────────────────────────────────────────────┘
```

Buffer-local maps: `dd` calls `review_queue.cancel_path(path_at_cursor)` then refreshes; `<CR>` opens the file with `vim.cmd("edit " .. path)`; `r` re-renders; `q` closes. The window auto-closes if queue empties. Exposed via `require("neph.api").queue()` and `:NephQueue` command.

`review_queue` gains `M.get_queue()` returning a shallow copy of the `queue` table (read-only snapshot). This avoids exposing the internal table directly.

### 6. Pre-submit summary — floating window in submit handler

Only shown when `session.get_total_hunks() >= 3`. Builds a scratch buffer with one line per hunk:

```
┌─ Review Summary ─────────────────────────────────┐
│  Hunk 1  ✓ accepted                              │
│  Hunk 2  ✗ rejected: off by one                  │
│  Hunk 3  ✗ rejected                              │
│  Hunk 4  ? undecided → will reject               │
│                                                  │
│  <CR> Confirm and submit    q Cancel             │
└──────────────────────────────────────────────────┘
```

`<CR>` proceeds with `do_finalize()` (which the summary closes first); `q` closes without finalizing. The summary is rendered via a local helper `show_submit_summary(session, on_confirm)` inside `start_review`, keeping it scoped to where `do_finalize` is accessible.

### 7. Gate winbar — `lua/neph/internal/gate_ui.lua`

New module. Uses a window-scoped extmark on a dedicated namespace `neph_gate_winbar` to append a gate indicator to the current window's winbar. Does NOT overwrite `vim.o.winbar` (global) — uses `vim.wo[win].winbar` on the window that was current when the gate changed. Cleared on gate release.

```lua
-- On hold:  winbar becomes "... %#WarningMsg# ⏸ NEPH HOLD %*"
-- On bypass: winbar becomes "... %#DiagnosticError# ⚡ NEPH BYPASS %*"
```

If the window's winbar is already non-empty, append with two spaces separator. If empty, set directly. Store the previous value in `gate_ui` state for proper restoration.

`lua/neph/api.lua` gate functions (`M.gate`, `M.gate_hold`, `M.gate_bypass`, `M.gate_release`) call `gate_ui.set(state)` / `gate_ui.clear()` after updating gate state.

## Risks / Trade-offs

- **Cursor restore + window validity**: The originating window may close during a long review. The `pcall` guards handle this gracefully (silent no-op).
- **Debounce timer + fast tests**: The 400ms defer means tests that assert notification content need to either call `vim.wait` or use the `_reset()` path. Existing tests don't assert queue notification content so this is not a regression risk.
- **Gate winbar clobbering**: Appending to a user's existing winbar string could produce visual artifacts if their winbar uses highlight groups that don't terminate cleanly. Mitigation: always append `%*` reset before our indicator.
- **Queue inspector stale state**: The floating buffer is a snapshot. If the queue changes while it's open, content is stale until `r` refresh. This is acceptable — the use case is inspection, not live monitoring.
