## MODIFIED Requirements

### Requirement: Pre-write review interception for peer agents

Peer adapters MAY install pre-write review interception that routes the host plugin's diff-approval flow through `neph.internal.review_queue` instead of the host plugin's native UI. Adapters that do so SHALL:

1. Install the override only when the corresponding peer flag is set on the agent definition (`peer.override_diff = true` for claudecode, `peer.intercept_permissions = true` for opencode).
2. Call `review_queue.enqueue` with the canonical request shape: `{ request_id: string, path: string, content: string, agent: string, mode = "pre_write", on_complete: fun(envelope) }`.
3. Generate a stable, unique `request_id` per interception event (recommended: `<plugin_kind>:<plugin_id>:<hrtime>`).
4. Honor gate state implicitly via the queue: `bypass` short-circuits to auto-accept before `open_fn` runs, `hold` queues silently, `normal` opens neph's review UI.
5. Translate the review envelope's `decision` field (`"accept"`/`"reject"`) into the host plugin's native response format inside `on_complete`, so the agent sees a single coherent answer.
6. No-op silently (with a one-time WARN log) if the host plugin's hook point is missing — never crash, never raise.

#### Scenario: claudecode override yields and resumes via coroutine

- **GIVEN** the claude-peer agent has `peer.override_diff = true`
- **AND** `claudecode.nvim` is installed and the override has been installed at peer-open time
- **WHEN** claude invokes the `openDiff` MCP tool, which calls `claudecode.diff.open_diff_blocking(old_path, new_path, new_contents, tab_name)`
- **THEN** the override SHALL call `review_queue.enqueue` with `{ request_id = "claudecode:<tab_name>:<hrtime>", path = new_path, content = new_contents, agent = "claude", mode = "pre_write", on_complete = <callback> }`
- **AND** the override SHALL `coroutine.yield()` to suspend the MCP request
- **AND** when the review resolves, `on_complete` SHALL `coroutine.resume(co, mcp_result)` where `mcp_result` is `{ content = { { type = "text", text = "FILE_SAVED" }, { type = "text", text = accepted_content } } }` on accept, or `{ content = { { type = "text", text = "DIFF_REJECTED" }, { type = "text", text = tab_name } } }` on reject
- **AND** `on_complete` SHALL also pump `_G.claude_deferred_responses[tostring(co)]` with the same `mcp_result` if that entry is set (parity with claudecode's deferred-response system)

#### Scenario: claudecode override under gate=bypass auto-accepts

- **GIVEN** the gate is `bypass`
- **AND** the claude-peer override is installed
- **WHEN** claude invokes `openDiff` for `path/to/file.lua` with `new_contents`
- **THEN** `review_queue.enqueue` SHALL call `_bypass_accept` before the UI opens
- **AND** `on_complete` SHALL fire in the same tick with `envelope.decision = "accept"` and `envelope.content = new_contents`
- **AND** the coroutine SHALL resume with `mcp_result = { content = { { type = "text", text = "FILE_SAVED" }, { type = "text", text = new_contents } } }`
- **AND** no review UI SHALL open

#### Scenario: opencode listener handles permission.asked via User autocmd

- **GIVEN** the opencode-peer agent has `peer.intercept_permissions = true`
- **AND** `opencode.nvim` is installed and connected to a running opencode server
- **AND** the listener has been installed via `User OpencodeEvent:permission.asked`
- **WHEN** opencode emits `OpencodeEvent:permission.asked` with `event.properties.permission = "edit"` and `event.properties.metadata = { filepath = <path>, diff = <unified-diff-string> }`
- **THEN** the listener SHALL apply the unified diff via `patch(1)` to derive the proposed content
- **AND** call `review_queue.enqueue` with `{ request_id = "opencode:<perm_id>:<hrtime>", path = filepath, content = proposed_content, agent = "opencode", mode = "pre_write", on_complete = <callback> }`
- **AND** when the review resolves, `on_complete` SHALL call `require("opencode.server").new(port):next(function(server) server:permit(perm_id, decision) end)` with `decision = "once"` on accept or `"reject"` on reject

#### Scenario: opencode peer suppresses native diff tab on open

- **GIVEN** the opencode-peer agent is being opened
- **WHEN** the peer adapter's `M.open()` runs
- **THEN** `vim.g.opencode_opts` SHALL be merged with `{ events = { permissions = { edits = { enabled = false } } } }` via `vim.tbl_deep_extend("force", ...)`
- **AND** opencode.nvim's native edit-diff autocmd handler SHALL exit at its `if not opts.edits.enabled then return end` guard
- **AND** only neph's review UI SHALL open for opencode permission events

#### Scenario: opencode listener handles permission.replied to clean up bypassed reviews

- **GIVEN** a review for `opencode:<perm_id>:*` is queued or active
- **WHEN** opencode emits `OpencodeEvent:permission.replied` for the same `perm_id` (e.g., the user replied via opencode's TUI directly)
- **THEN** the listener SHALL cancel the corresponding queue entry by `path` so the orphaned review does not block the queue
- **AND** if the review was active, the UI SHALL close cleanly

#### Scenario: peer plugin missing leaves native behavior intact

- **GIVEN** the agent definition sets `peer.override_diff = true` (or `peer.intercept_permissions = true`)
- **AND** the corresponding peer plugin (`claudecode.nvim` / `opencode.nvim`) is not installed
- **WHEN** the peer adapter's `M.open()` runs
- **THEN** `is_available()` SHALL return `false` and `M.open()` SHALL emit a one-time notification
- **AND** no autocmds, augroups, or function-table overrides SHALL be installed
- **AND** other agents SHALL continue functioning normally

#### Scenario: patch failure on opencode side surfaces visibly

- **GIVEN** opencode emits `permission.asked` with a `metadata.diff` that `patch(1)` cannot apply (corrupted, mismatched line numbers, missing `patch` binary)
- **WHEN** the listener attempts to derive proposed content
- **THEN** the listener SHALL log at WARN level via `log.warn("peers.opencode", ...)` with the file path
- **AND** SHALL emit a `vim.notify("Neph: could not apply opencode diff for <path> — allowing edit", WARN)` notification
- **AND** SHALL call `Server:permit(perm_id, "once")` to unblock opencode (default policy: auto-allow on patch failure with visible warning; opt-in to auto-reject via config in a future change)

### Requirement: Override installation is idempotent and revertible

Peer adapters that monkey-patch host-plugin functions SHALL guard against double-installation and SHALL provide a `_reset` test hook for clearing internal install state.

#### Scenario: Double-install is a no-op

- **WHEN** `M.open()` is called twice in the same nvim session for a peer agent with `override_diff = true`
- **THEN** the host-plugin function SHALL be patched at most once (the second call SHALL detect `override_installed = true` and return early)

#### Scenario: Reset clears install state for tests

- **WHEN** `M._reset()` is called
- **THEN** `override_installed` SHALL be set to `false`
- **AND** the next `M.open()` call MAY re-install the override

### Requirement: Canonical request_id and gate-aware queue contract

All callers of `review_queue.enqueue` from peer adapters SHALL provide a non-empty string `request_id`. The queue SHALL drop requests with missing or empty `request_id` (existing behavior; this requirement makes it explicit for peer adapters).

#### Scenario: Missing request_id is dropped

- **WHEN** a peer adapter calls `review_queue.enqueue` without a `request_id` field
- **THEN** the queue SHALL log at debug level and emit a `"Neph: review dropped — request_id is required"` notification
- **AND** SHALL NOT open a review UI
- **AND** the agent SHALL eventually time out or receive a synthesized response from the adapter (adapter responsibility, not the queue's)

## REMOVED Requirements

### Requirement: opencode_sse integration group activates SSE permission interception

**Reason**: never functionally connected. The integration group existed in `config.defaults` but no agent definition (including `opencode-peer`) ever set `integration_group = "opencode_sse"`, so the SSE subscription wired into `session.lua` never started. The User-autocmd-based interception in this change replaces the role this requirement was meant to fill, with a more reliable seam.

**Migration**: users with `integration_groups.opencode_sse = ...` in their `setup({...})` config get a one-line CHANGELOG note. The group is hard-removed; setting it has no effect (it falls through to the default group). No deprecation period — the feature was non-functional, so there is no behavior to preserve.
