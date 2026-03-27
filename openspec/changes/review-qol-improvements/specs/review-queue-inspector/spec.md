## ADDED Requirements

### Requirement: queue-inspector-command

`:NephQueue` command opens the queue inspector. Equivalent to calling `require("neph.api").queue()`. Available at all times (not just during an active review).

### Requirement: queue-inspector-display

The inspector displays a centered floating window (`relative="editor"`, `border="rounded"`) with:
- A header line showing total count: `"Neph Review Queue (N pending)"`
- One line for the active review prefixed with `● ACTIVE`
- Numbered lines for each queued review (1-indexed)
- Each line shows: truncated relative file path (35 chars max) and agent name
- A footer hint line: `"dd=cancel  <CR>=jump  r=refresh  q=close"`
- If queue is empty and no active review: shows `"Queue is empty"` and closes after 1.5s

### Requirement: queue-inspector-keymaps

Buffer-local normal-mode keymaps on the inspector buffer:
- `dd`: cancel the review at the cursor line (calls `review_queue.cancel_path`), then refresh
- `<CR>`: open the file at cursor line in the previous window (`vim.cmd("edit " .. path)`)
- `r`: re-render the buffer contents from current queue state
- `q` / `<Esc>`: close the floating window

### Requirement: queue-accessor

`review_queue.get_queue()` returns a shallow copy of the pending queue array (not the live table). Used by the inspector to read queue state without exposing mutable internals.

### Requirement: queue-api-function

`require("neph.api").queue()` opens the queue inspector. Added to the public API module.
