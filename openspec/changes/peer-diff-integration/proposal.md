## Why

The `frictionless-by-default` change introduced peer adapters for `claudecode.nvim` and `opencode.nvim`, including a flag (`agent.peer.override_diff`) intended to route the peer plugins' diff approvals through neph's review queue so users see a single, consistent review UI regardless of which agent fired the write.

That flag has never actually worked:

- **claudecode override is unreachable.** `lua/neph/peers/claudecode.lua:ensure_diff_override` looks for `claudecode.tools.handlers` (and `claudecode.tools._handlers`). Neither exists. The real registry is `claudecode.tools.tools[name].handler` and the real blocking entry-point is `claudecode.diff.open_diff_blocking`. `ensure_diff_override` early-exits at the "API may have changed" debug log, so claude has been showing its native vimdiff for every diff approval despite the flag being on.
- **claudecode override has the wrong queue contract.** Even if it installed, it calls `review_queue.enqueue({ source, file, proposed_content, on_resolved })`. The queue requires `{ request_id, path, content, on_complete }` and rejects entries missing `request_id` with a "review dropped" notification. So a "fixed" install would still be a no-op.
- **opencode pre-write interception is unwired.** `lua/neph/internal/opencode_sse.lua` + `lua/neph/reviewers/opencode_permission.lua` exist and would dispatch reviews on `permission.asked`, but `opencode-peer.lua` has no `integration_group = "opencode_sse"`, so the SSE subscription never starts. The permission handler also reads the wrong field name (`metadata.path` vs opencode's `metadata.filepath`) and shells out to `curl` directly instead of using opencode.nvim's `Server:permit` API. It silently auto-allows when `patch(1)` fails to apply the diff — a permissive failure mode that surprises users running `gate=normal`.

The end-state we want: when `gate=normal` (or `hold`), agent-initiated edits open in neph's review UI, with the same keymaps and queueing semantics as fs-watcher post-write reviews and `<leader>jr` manual reviews. When `gate=bypass`, the bypass short-circuit fires inside the queue (already implemented) and the agent's MCP/HTTP response returns "accepted" in the same tick — zero added friction.

## What Changes

- **MODIFIED** `peer-adapter` capability: peer adapters declaring `peer.override_diff = true` (claudecode) or `peer.intercept_permissions = true` (opencode) MUST install pre-write review interception that hands off to `neph.internal.review_queue` using the canonical request shape, and MUST honor gate state (bypass auto-accepts, hold queues, normal opens UI).
- **REWRITTEN** `lua/neph/peers/claudecode.lua` diff override:
  - Hook `claudecode.diff.open_diff_blocking` (not the non-existent `tools.handlers.openDiff`).
  - Coroutine-aware: yield until review_queue resolves, resume with MCP-shaped result `{content = {{type="text", text="FILE_SAVED"|"DIFF_REJECTED"}, {type="text", text=...}}}`.
  - Also pump `_G.claude_deferred_responses[tostring(co)]` for parity with claudecode's deferred-response system.
  - Use canonical `enqueue` shape: `{request_id, path, content, agent="claude", mode="pre_write", on_complete}`.
- **REWRITTEN** `lua/neph/peers/opencode.lua` permission interception:
  - Listen to `User OpencodeEvent:permission.asked` autocmd (opencode.nvim already maintains the SSE subscription and re-emits typed events).
  - Filter `permission == "edit"`, read `metadata.diff` + `metadata.filepath`, apply unified diff with `patch(1)` to derive proposed content.
  - Hand off to `review_queue.enqueue` with canonical shape; on completion call opencode.nvim's `Server:permit(id, "once"|"reject")`.
  - Suppress opencode.nvim's native diff tab by setting `vim.g.opencode_opts.events.permissions.edits.enabled = false` from the peer adapter's `setup()` (idempotent, doesn't clobber other user-set keys).
- **DELETED**: `lua/neph/internal/opencode_sse.lua`, `lua/neph/reviewers/opencode_permission.lua`, the `opencode_sse` integration_group entry in `lua/neph/config.lua`, and the SSE subscription wiring in `lua/neph/internal/session.lua`. opencode.nvim's User-autocmd path replaces all of it.
- **PRESERVED**: `<leader>jr` manual review and fs-watcher post-write review remain agent-agnostic and unchanged.
- **PRESERVED**: gate semantics. `_bypass_accept` short-circuit fires before `open_fn`, so bypass-mode users see zero new behavior except the previously-broken claudecode override now correctly auto-resolves the MCP response.

## Capabilities

### Modified Capabilities

- `peer-adapter` — adds the pre-write review interception requirement (override_diff / intercept_permissions hooks) and specifies the queue-contract shape both implementations must use.

## Impact

### Lua plugin

- `lua/neph/peers/claudecode.lua` — full rewrite of `ensure_diff_override` and the `M.send`/`M.focus`/`M.is_visible`/`M.hide` paths. New private `_install_diff_override(claude_diff_module)` function.
- `lua/neph/peers/opencode.lua` — add `User OpencodeEvent:permission.asked` listener in `M.open()`, helper to apply unified diffs, removal of any references to the old SSE/permission modules.
- `lua/neph/agents/opencode-peer.lua` — add `peer.intercept_permissions = true` flag. Drop any reliance on `integration_group = "opencode_sse"`.
- `lua/neph/agents/claude-peer.lua` — keep `peer.override_diff = true`; field semantics now actually work.
- `lua/neph/internal/session.lua` — remove the `agent.integration_group == "opencode_sse"` SSE-subscribe block (~15 lines, including pcall and log).
- `lua/neph/config.lua` — remove `integration_groups.opencode_sse`. Document migration in CHANGELOG.
- `lua/neph/internal/opencode_sse.lua` — DELETED.
- `lua/neph/reviewers/opencode_permission.lua` — DELETED.
- Existing tests touching the deleted modules — DELETED. New tests:
  - claudecode peer: override installs on `open()`, accepts → MCP `FILE_SAVED`, rejects → MCP `DIFF_REJECTED`, bypass → auto-accept without UI.
  - opencode peer: User-autocmd listener fires, calls `Server:permit("once")` on accept and `"reject"` on reject, no-ops when peer not installed.

### User-facing config

- Users with `integration_groups.opencode_sse = ...` in their config will see a one-time deprecation notice; the group becomes a no-op alias for `default`. (Or — see design.md — accept hard removal since it never worked.)
- Users do not need to set `vim.g.opencode_opts.events.permissions.edits.enabled = false` manually; the peer adapter does it automatically when the opencode-peer agent opens. Power users can override by setting it back to `true` in their config (last-write-wins via `vim.tbl_deep_extend`).

### CHANGELOG / docs

- README: mention that claude/opencode peer agents now route diff approvals through neph's review UI when `gate ≠ bypass`.
- Document the deletion of `opencode_sse` integration group.
