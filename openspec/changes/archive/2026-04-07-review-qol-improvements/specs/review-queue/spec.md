## MODIFIED Requirements

### Requirement: debounced-batch-notifications

**Updated behavior**: Per-enqueue notifications for queued (not first/active) reviews are debounced. Instead of notifying on every `table.insert(queue, params)` call, a 400ms `vim.defer_fn` timer accumulates pending notifications. When the timer fires, a single notification is emitted: `"N reviews queued (agent1, agent2)"` grouping unique agent names. If only one agent, format is `"N reviews queued (agent)"`. If agent is nil, omit the parenthetical.

The first review that opens immediately (the `not active` path) retains its existing immediate notification behavior (no change). The timer is cancelled and `pending_notify_batch` cleared in `M._reset()`.

### Requirement: get-queue-accessor

**Added behavior**: `M.get_queue()` returns a shallow copy (`vim.deepcopy`) of the internal `queue` table. Does not expose the live table. Used by the queue inspector UI.
