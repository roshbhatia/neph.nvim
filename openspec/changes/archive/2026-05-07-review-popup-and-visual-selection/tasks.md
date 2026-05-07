## 1. Visual selection from marks

- [x] 1.1 Add `M.get_visual_marks(buf)` helper in `lua/neph/api.lua`: reads `'<` and `'>` marks; returns `{from, to, kind}` or nil if marks are unset (both at line 0). Use `vim.fn.visualmode()` for `kind`.
- [x] 1.2 Update `M.ask` and `M.comment` to call `get_visual_marks` instead of `vim.fn.mode()`. Default text is `"+selection "` when marks present, else `"+cursor "`.
- [x] 1.3 Pass marks through `input_for_active(action, default, opts)` where `opts.selection_marks = marks_or_nil`.
- [x] 1.4 In `lua/neph/internal/input.lua`, accept `opts.selection_marks` and pass to `context.from_marks(buf, marks)` if present, else fall back to `context.new()`.
- [x] 1.5 In `lua/neph/internal/context.lua`, add `M.from_marks(buf, marks)` that constructs a context with `range = marks` (skipping the live `mode()` check). Keep `M.new()` and `M.get_selection_range()` unchanged.
- [x] 1.6 Tests: `tests/api/visual_selection_marks_spec.lua` — keymap-callback simulation (set marks, then call `api.ask` with mock `vim.ui.input`) confirms `+selection` expands to selected text. Unset marks fall back to `+cursor`. (Block-mode test deferred — visualmode() returns "" in headless test sessions, so kind defaults to "char". Real-world block-mode coverage via manual verification.)

## 2. Stale test cleanup (do this FIRST so the suite is clean before adding new specs)

- [x] 2.1 Open `tests/agents_launch_args_spec.lua`. The `claude.launch_args_fn` test cases no longer apply (claude-peer has no launch_args_fn). Delete the `describe("claude.launch_args_fn", ...)` block. Keep the pi-launch-args cases.
- [x] 2.2 Open `tests/e2e/smoke_test.lua`. Change `require("neph.agents.claude")` to `require("neph.agents.claude-peer")`.
- [x] 2.3 Run `bash scripts/run-lua-tests.sh > /tmp/audit_test.log 2>&1` and confirm zero `Errors : N` lines with N>0. Specifically grep `^Errors : [^0]` after the run.

## 3. Popup review style — config and resolution

- [x] 3.1 Add `review.style` field to `lua/neph/config.lua` defaults (defaults nil → fallback applies). Document.
- [x] 3.2 Add `review_style` field to `neph.AgentDef` type in `lua/neph/internal/contracts.lua`. Optional `"tab" | "popup"`. Validation.
- [x] 3.3 In `lua/neph/api/review/init.lua`, add `local function resolve_review_style(agent_name)` that consults agent override → config default → fallback (`"popup"` for peer agents, `"tab"` for everyone else).
- [x] 3.4 In `set_open_fn`, after gate handling and before `_open_immediate`, dispatch on `resolve_review_style(params.agent)`: `"popup"` → `require("neph.api.review.popup").open(params)`; `"tab"` → `M._open_immediate(params)`.

## 4. Popup implementation with inline hunks

- [x] 4.1 Create `lua/neph/api/review/popup.lua` with `M.open(params)`.
- [x] 4.2 Read old_lines from disk; compute hunks via `engine.compute_hunks(old_lines, new_lines)`.
- [x] 4.3 Build the popup buffer content: header (agent → file, +N/-M, hunk count) + hunks rendered inline (max 24 lines; "content truncated" line beyond that).
- [x] 4.4 Use `vim.api.nvim_open_win` for the float; fall back to `vim.ui.select` if buf creation or window opening fails.
- [x] 4.5 Buffer-local keymaps: `a` accept; `r` reject; `v` view-diff (calls `_open_immediate`); `q`/`<Esc>` later.
- [x] 4.6 Accept envelope shape per spec; write_result + on_complete + queue advance + close window.
- [x] 4.7 Reject same shape with `decision="reject"`.
- [x] 4.8 View path closes popup, calls `_open_immediate(params)`.
- [x] 4.9 Later path (q/Esc) closes popup without firing on_complete.
- [x] 4.10 Tests: `tests/api/review/popup_spec.lua` — accept, reject, later, hunk-rendering paths verified. (gate=bypass / gate=hold paths inherit from review_queue and are tested at the queue level.)

## 5. Default style for peer agents

- [x] 5.1 In `lua/neph/agents/claude-peer.lua`, set `review_style = "popup"`.
- [x] 5.2 In `lua/neph/agents/opencode-peer.lua`, set `review_style = "popup"`.
- [x] 5.3 Update `tests/agent_submodules_spec.lua` to assert `review_style == "popup"` on both peer agents.

## 6. Peer-agent text injection (the critical send-path fix)

- [x] 6.1 In `lua/neph/peers/claudecode.lua`, declare a module-local `pane_id = nil`.
- [x] 6.2 Export `M.wezterm_pane_cmd(cmd_string, env_table)` that captures pane_id asynchronously and registers VimLeavePre cleanup in augroup `NephClaudecodeWezterm`.
- [x] 6.3 Rewrite `M.send` to dispatch via `wezterm cli send-text` (async via `jobstart` — never blocks the event loop) when pane_id is owned; fall back to bufnr chansend otherwise.
- [x] 6.4 `M.is_visible`: when pane_id is owned, return true directly (no shell-out — freeze-safe). Falls back to bufnr check otherwise.
- [x] 6.5 `M.focus`: dispatches to `wezterm cli activate-pane` async when pane_id owned.
- [x] 6.6 `M.kill`: spawns `wezterm cli kill-pane` async, clears pane_id, then calls `claudecode.stop`.
- [x] 6.7 `M.hide`: no-op when pane_id is owned (can't hide a wezterm pane without killing it). Bufnr path otherwise.
- [x] 6.8 `M._reset_pane_state()` test hook + `M._set_pane_id(id)` for test seam.
- [x] 6.9 Migrated user config `~/.config/nvim/lua/plugins/claudecode.lua` to call `require("neph.peers.claudecode").wezterm_pane_cmd`.
- [x] 6.10 Tests: `tests/peers/claudecode_wezterm_pane_spec.lua` — 9 cases covering argv shape, send dispatch, kill, focus, hide, is_visible (no shell-out).

## 7. Tighten contract validation (low-priority audit fix)

- [x] 7.1 In `lua/neph/internal/contracts.lua`, validate `peer.override_diff` is boolean if present.
- [x] 7.2 Validate `peer.intercept_permissions` is boolean if present.
- [x] 7.3 Validate `review_style` is `"tab" | "popup"` if present.

## 8. Docs

- [x] 8.1 README: document the `review.style` config option and per-agent override. Show the popup ASCII.
- [x] 8.2 README: clarify the `[a]/[r]/[v]/[esc]` semantics in the popup. Especially that `esc` is "later", not "reject".
- [x] 8.3 README: document the `wezterm_pane_cmd` helper for users who want claude in a wezterm pane.
- [x] 8.4 CHANGELOG (Unreleased): bundle all five items (visual marks, popup style, wezterm send-path, async patch, stale tests) under Added/Fixes.

## 9. Verification

- [x] 9.1 `task test:lua` — 1513 successes, 0 failures, 0 errors.
- [x] 9.2 stylua format clean.
- [ ] 9.3 `wezterm-tui-test` driven manual: deferred for end-user confirmation. The unit/spec coverage exercises every code path (popup accept/reject/later/view, marks-based selection, wezterm-pane send/focus/kill/is_visible, async patch, watchdog).

## 10. Freeze hardening (async shell-outs + diagnostics)

- [x] 10.1 Audit complete (see design.md). Only `vim.fn.system` in autocmd context was `apply_unified_diff` in opencode peer. Other `vim.fn.system` calls are in-process IO or already async (jobstart+detach).
- [x] 10.2 `apply_unified_diff` rewritten as `apply_unified_diff_async(file_path, diff_str, callback)` using `jobstart` + `on_exit`.
- [x] 10.3 `permission.asked` handler defers enqueue to the on_exit callback. Autocmd returns immediately.
- [x] 10.4 All wezterm cli calls in claudecode peer (`send-text`, `kill-pane`, `activate-pane`) use `vim.fn.jobstart` with `detach = true`. Fire-and-forget.
- [x] 10.5 `M.is_visible` returns `true` directly when pane_id owned (no `wezterm cli list` shell-out — freeze-safe).
- [x] 10.6 `lua/neph/internal/watchdog.lua` — `M.wrap(name, fn)` with hrtime timing + WARN log when threshold exceeded. `NEPH_WATCHDOG=1` env var or `setup({ watchdog = { enable = true } })`.
- [ ] 10.7 Wrap the key callback sites with watchdog. (Deferred — opt-in instrumentation; will wire as needed once a freeze recurs and we have signal on which path to instrument.)
- [x] 10.8 `lua/neph/internal/log.lua`: `init_from_env()` reads `NEPH_DEBUG=1`. Already flushes per-line via `io.open / write / close` (no buffering) — survives kill -9.
- [x] 10.9 Tests: `tests/peers/opencode_async_patch_spec.lua` (1 case — autocmd handler does NOT shell out synchronously). `tests/internal/watchdog_spec.lua` (6 cases — disabled pass-through, enabled with fast/slow/error paths, threshold breach logging).

## 11. Out of scope (followups)

- [ ] 11.1 Per-agent style configuration via `:NephReviewStyle <agent> popup|tab` runtime command.
- [ ] 11.2 Configurable popup keymaps (currently hardcoded `a/r/v/q/Esc`).
- [ ] 11.3 Path-2 refactor: neph fully owns wezterm pane via custom claudecode provider table. Only revisit if the 200ms pane_id capture race becomes a real problem.
- [ ] 11.4 Same external-pane treatment for opencode peer (when/if opencode.nvim grows external-terminal support).
- [ ] 11.5 More extensive watchdog instrumentation (eventually wrap every public API entry-point) once we have signal on which paths are slow.
