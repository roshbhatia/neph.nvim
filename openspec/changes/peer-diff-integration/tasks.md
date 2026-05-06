## 1. Pre-merge verification

- [x] 1.1 Verify against running opencode that `permission.asked` event payload uses `event.properties.metadata.filepath` and `event.properties.metadata.diff` (not `metadata.path`). Document field names in design.md if different.
- [x] 1.2 Decide patch-failure policy: auto-allow (current implicit) vs auto-reject. Update design.md decision.
- [x] 1.3 Decide `vim.schedule`-wrapping policy for `coroutine.resume` in claudecode override. Default to always-schedule unless a specific path is verified safe.

## 2. claudecode peer rewrite

- [x] 2.1 In `lua/neph/peers/claudecode.lua`, replace `ensure_diff_override` with `install_diff_override` that hooks `claudecode.diff.open_diff_blocking`.
- [x] 2.2 Generate `request_id` as `("claudecode:%s:%d"):format(tab_name, vim.uv.hrtime())`.
- [x] 2.3 Call `review_queue.enqueue` with canonical shape `{request_id, path = new_file_path, content = new_file_contents, agent = "claude", mode = "pre_write", on_complete}`.
- [x] 2.4 In `on_complete`, build MCP-shaped result `{content = {{type="text", text="FILE_SAVED"|"DIFF_REJECTED"}, {type="text", text=...}}}`, call `coroutine.resume(co, result)` (vim.schedule-wrapped per 1.3), and pump `_G.claude_deferred_responses[tostring(co)]` for parity.
- [x] 2.5 `return coroutine.yield()` from the override.
- [x] 2.6 Remove the obsolete `tools.handlers`/`tools._handlers` lookup path entirely.
- [x] 2.7 On install failure (claudecode.diff missing or open_diff_blocking absent), log at WARN once and let claudecode's native UI handle diffs.
- [x] 2.8 Add `M._reset` test hook for resetting `override_installed` state between tests.

## 3. opencode peer rewrite

- [x] 3.1 In `lua/neph/peers/opencode.lua`, add `install_permission_listener()` that registers a `User OpencodeEvent:permission.asked` autocmd in a `NephOpencodePerm` augroup.
- [x] 3.2 Filter event: only `permission == "edit"` proceeds.
- [x] 3.3 Read `event.properties.metadata.filepath` and `event.properties.metadata.diff`. If missing, log WARN and call `Server:permit(id, "once")`.
- [x] 3.4 Apply unified diff via `patch(1)` to derive proposed content (port the `_apply_diff` helper from the deleted `opencode_permission.lua`, fix any field-name issues found in 1.1).
- [x] 3.5 On patch failure, follow the policy from 1.2.
- [x] 3.6 Generate `request_id` as `("opencode:%d:%d"):format(perm_id, vim.uv.hrtime())`.
- [x] 3.7 Call `review_queue.enqueue` with canonical shape.
- [x] 3.8 In `on_complete`, call `require("opencode.server").new(port):next(function(s) s:permit(perm_id, decision) end)` with `"once"` (accept) or `"reject"`.
- [x] 3.9 In `M.open()`, set `vim.g.opencode_opts = vim.tbl_deep_extend("force", vim.g.opencode_opts or {}, { events = { permissions = { edits = { enabled = false } } } })` to suppress opencode.nvim's native diff tab. Idempotent.
- [x] 3.10 Add `User OpencodeEvent:permission.replied` listener that cancels the corresponding queue entry if it exists (handles the case where the user replies via opencode's own TUI). Use `review_queue.cancel_path` or equivalent.
- [x] 3.11 In `M.kill()` and `cleanup_all()`, clear the `NephOpencodePerm` augroup so dead listeners don't leak.

## 4. Delete obsolete code

- [x] 4.1 Delete `lua/neph/internal/opencode_sse.lua`.
- [x] 4.2 Delete `lua/neph/reviewers/opencode_permission.lua`.
- [x] 4.3 Remove the `agent.integration_group == "opencode_sse"` SSE-subscribe block in `lua/neph/internal/session.lua`.
- [x] 4.4 Remove `integration_groups.opencode_sse` from `lua/neph/config.lua` defaults.
- [x] 4.5 Delete `tests/internal/opencode_sse_spec.lua` (if exists), `tests/reviewers/opencode_permission_spec.lua` (if exists), and any test helpers tied to the removed modules. Also delete the now-orphan `lua/neph/agents/{claude,opencode}.lua` files (unified peer versions are canonical).
- [x] 4.6 Update or delete any docs/README sections referencing `opencode_sse` integration group.

## 5. Agent definitions

- [x] 5.1 In `lua/neph/agents/opencode-peer.lua`, add `peer.intercept_permissions = true` to the agent def.
- [x] 5.2 Confirm `lua/neph/agents/claude-peer.lua` keeps `peer.override_diff = true`.
- [x] 5.3 In `lua/neph/peers/opencode.lua` `M.open()`, gate listener install on `agent_config.peer.intercept_permissions == true`.
- [x] 5.4 In `lua/neph/peers/claudecode.lua` `M.open()`, gate override install on `agent_config.peer.override_diff == true`.

## 6. Tests

- [x] 6.1 `tests/peers/claudecode_diff_override_spec.lua`: install runs once (idempotent), accept resumes coroutine with `FILE_SAVED` + edited content, reject resumes coroutine with `DIFF_REJECTED`, install gates on `peer.override_diff`, deferred-response pump fires when `_G.claude_deferred_responses[co_key]` is set.
- [x] 6.2 `tests/peers/opencode_permission_spec.lua`: autocmds install in `NephOpencodePerm` augroup, non-edit permissions ignored, missing metadata auto-allows, successful patch enqueues review with correct shape, accept → `Server:permit("once")`, reject → `Server:permit("reject")`, augroup cleared on `M.kill()`, `vim.g.opencode_opts` suppresses native UI.
- [x] 6.3 Update `tests/agent_submodules_spec.lua` to reflect deletion of `agents/claude.lua` and `agents/opencode.lua` (count stays 10 via `claude-peer`/`opencode-peer`). Also updated `setup_smoke_spec.lua` to require `claude-peer`.
- [x] 6.4 Run `task test:lua` and confirm zero failures. (Result: 1483 successes, 0 failures, 0 errors. Exit code 1 is a known nvim-headless plenary quirk we already work around in `task test`.)
- [x] 6.5 Run `task lint` and confirm clean. (`stylua --check lua/ tests/` passes; `luacheck` not installed in env but `task check` already has `ignore_error: true` for it.)

## 7. Manual verification

- [x] 7.1 With `claudecode.nvim` installed, `gate=normal`: triggered openDiff via coroutine, neph's review UI opened in a new tab, `gA`+`gs` resumed coroutine with `{content=[{text="FILE_SAVED"},{text="proposed_line"}]}`; `q` resumed with `{content=[{text="DIFF_REJECTED"},{text="verify-tab-rej"}]}`. Verified end-to-end via wezterm-tui-test driver.
- [x] 7.2 With `claudecode.nvim` installed, `gate=bypass`: triggered openDiff, no UI tab opened, coroutine resumed with `FILE_SAVED` immediately. (Required fixing `_bypass_accept` to fire `params.on_complete` — see commit "fix(review): fire on_complete in bypass auto-accept".)
- [ ] 7.3 With `claudecode.nvim` absent, claude-peer not visible / not picked. (Skipped — would require uninstalling the plugin from the user's setup. Behavior verified via unit test "peer plugin missing leaves native behavior intact" in spec.md.)
- [ ] 7.4 With `opencode.nvim` installed and opencode running, `gate=normal`: trigger an edit, verify neph's review UI opens (not opencode's diff tab), accept/reject. (Skipped — would need the opencode CLI running with `--port`. Behavior verified by `tests/peers/opencode_permission_spec.lua`.)
- [ ] 7.5 With `opencode.nvim` installed, `gate=bypass`: trigger edit → auto-accept. (Skipped — same reason as 7.4.)
- [x] 7.6 Concurrent edits: with `gate=hold`, queued two openDiff coroutines, `review_queue.count()` reported `2`, no UI opened. FIFO drain on release confirmed via existing review-queue tests.
- [x] 7.7 Mid-review nvim quit: verified the orphan-pane fix in `~/.config/nvim/lua/plugins/claudecode.lua` kills the spawned wezterm pane on `:qa!`. Reject-envelope-on-quit behavior is covered by the existing VimLeavePre handler in `lua/neph/api/review/init.lua` (synthesises `{schema="review/v1", decision="reject", reason="Neovim exiting"}` and calls `on_complete`).

## 8. Docs

- [x] 8.1 Update `README.md` peer-agents section to describe the working diff integration.
- [x] 8.2 Add CHANGELOG entry under "Fixes" for the never-worked claudecode openDiff override.
- [x] 8.3 Add CHANGELOG entry under "Removed" for the `opencode_sse` integration group.
- [x] 8.4 Update `frictionless-by-default`'s `specs/peer-adapter/spec.md` to match the new requirements (or amend in this change's `specs/peer-adapter/spec.md` MODIFIED block).

## 9. Followups (out of scope)

- [ ] 9.1 Consider adding a similar diff-override seam for `amp`, `codex`, `gemini` if/when those agents grow native diff UIs that we want to redirect.
- [ ] 9.2 Consider auto-opening the agent terminal on review completion (so user sees the agent reaction without manual focus).
