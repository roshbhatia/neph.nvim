## Why

Manual verification of `peer-diff-integration` surfaced four interconnected UX/correctness gaps that all gate the same workflow ("driving claude from inside nvim"). Bundling them keeps the change reviewable as one coherent fix rather than four trickling PRs:

1. **Visual-mode `<leader>ja`/`<leader>jc` lose the selection.** When the user selects text and presses the keymap, nvim exits visual mode before the callback runs. `vim.fn.mode()` returns `"n"`, so `api.ask`/`api.comment` fall back to `"+cursor "` instead of `"+selection "`. The `'<` and `'>` marks are set correctly but no code reads them. `context.get_selection_range` gates on the same broken `mode()` check.

2. **The vimdiff review tab is heavyweight for routine accept/reject.** Under `gate=normal`, every claude write opens a full vimdiff tab with eight keymaps. For most decisions a `[A]ccept / [R]eject / [V]iew diff` floating popup is enough — and matches the lightweight feel users expect from peer-plugin-driven workflows. The popup should also render the actual hunks (using neph's existing `engine.compute_hunks`) rather than just summarising `+N / -M`.

3. **🔴 Critical: peer-claude `<leader>ja` text never reaches claude when using `terminal.provider = "external"`.** The user's config (which we set together so claude opens in a wezterm split-pane) means `claudecode.terminal.get_active_terminal_bufnr()` returns nil — the bufnr doesn't exist; claude runs in a wezterm pane managed by the wezterm daemon. Our `M.send` chansend path silently no-ops, breaking every keymap that goes through `session.ensure_active_and_send`: `<leader>ja`, `<leader>jf`, `<leader>jc`, `<leader>jv`, and all `<leader>dr*` diff-review actions. Same fix unblocks the diff-hunk-review tool flow.

4. **Stale test refs to deleted modules.** `tests/agents_launch_args_spec.lua:25` and `tests/e2e/smoke_test.lua:33` still `require("neph.agents.claude")`. Plenary reports these as ERRORS (not failures); our previous filter only checked failures and missed it. Real test errors shipping in main.

All four are blocking the "frictionless when bypass, helpful when involved" experience the prior change-track set out to deliver. Bypass already works; this change makes the involved-mode experience actually function.

## What Changes

### Visual-mode selection capture

- **MODIFIED** `agent-lifecycle` capability: `api.ask` and `api.comment` SHALL read the visual-selection bounds from the `'<` and `'>` marks, not from `vim.fn.mode()`. When the marks bound a non-empty range in the current buffer, the action SHALL prefill the input with `"+selection "` and `placeholders.apply` SHALL expand it from those marks. New `context.from_marks(buf, marks)` constructor leaves `context.new()` and `context.get_selection_range()` unchanged, so `auto-context-broadcast` snapshots are not polluted by stale visual marks.

### Popup review style + hunk rendering

- **MODIFIED** `review-ui` capability: introduce `review.style` config option (`"tab"` default, `"popup"` opt-in) and per-agent `review_style` override. Peer agents (`type = "peer"`) default to `"popup"`; non-peer agents default to `"tab"`.
- **NEW** `lua/neph/api/review/popup.lua` module: floating window using `Snacks.win` (with `vim.ui.select` fallback). Shows agent name, file path, hunk count, AND the actual hunks rendered inline using `engine.compute_hunks(old_lines, new_lines)`. Single-key resolution: `a` accept, `r` reject, `v` flip to existing vimdiff tab, `q`/`<Esc>` defer to queue.
- Honors gate state — bypass/hold short-circuit before the popup reaches `open_fn`.
- Hunk display is bounded (max ~10 lines visible; scrollable via `<C-d>`/`<C-u>` inside the popup).

### Peer-agent text injection (the critical fix)

- **NEW** helper `M.wezterm_pane_cmd(cmd_string, env_table)` exported from `lua/neph/peers/claudecode.lua`. When wired into claudecode's `terminal.provider_opts.external_terminal_cmd` (function form), neph takes ownership of the wezterm-pane spawn and tracks the resulting pane_id internally.
- **MODIFIED** `lua/neph/peers/claudecode.lua` `M.send` / `M.is_visible` / `M.focus` / `M.kill` / `M.hide`: when the adapter has a tracked `pane_id` (i.e., we own the wezterm pane), use `wezterm cli send-text` / `activate-pane` / `kill-pane` / `list` against that pane. When no pane_id is tracked (e.g., user is on snacks/native provider), fall back to the existing chansend path.
- **NEW** registers a `VimLeavePre` autocmd inside the peer adapter that kills the tracked pane on quit (replaces the orphan-pane logic in user's config — moves it into the canonical place).
- **MIGRATED** user's `~/.config/nvim/lua/plugins/claudecode.lua` to call `require("neph.peers.claudecode").wezterm_pane_cmd` instead of inlining the pane-tracking logic.

### Stale test cleanup

- **FIXED** `tests/agents_launch_args_spec.lua`: require `neph.agents.claude-peer` (the canonical claude agent file).
- **FIXED** `tests/e2e/smoke_test.lua`: same.
- Add a sanity assertion: `tests/setup_smoke_spec.lua` already requires `claude-peer`; verify the spec runs without errors after fixes (not just passes).

### Freeze hardening

User reports recurring "fully frozen nvim" after using the plugin. Without a stack trace we can't pinpoint, but synchronous shell-outs in autocmd / coroutine-callback hot paths are the prime suspect — every `vim.fn.system(...)` blocks the main loop until the subprocess returns. If `patch`, `wezterm`, or `curl` is slow / hung, nvim freezes.

- **REWRITTEN** `lua/neph/peers/opencode.lua`'s `apply_unified_diff` to use `vim.fn.jobstart` with `on_exit`/`on_stdout` callbacks. The autocmd handler captures the event, kicks off the patch async, and `review_queue.enqueue` runs from the on_exit callback. The autocmd handler returns immediately so the libuv event loop is never blocked.
- **ASYNC** all `wezterm cli send-text` / `kill-pane` / `activate-pane` calls in the new `M.send` / `M.kill` / `M.focus` paths via `vim.fn.jobstart` (fire-and-forget; we don't need stdout). No new sync shell-outs introduced by this change.
- **NO LIST-CALL IN is_visible**: `M.is_visible` SHALL NOT shell out to `wezterm cli list`. It returns `pane_id ~= nil` as a proxy. If the pane was externally killed, the next `send` will silently fail (and we already log that). Worst-case staleness is small; freeze risk eliminated.
- **DIAGNOSTIC LOGGING** survives freezes: `lua/neph/internal/log.lua` SHALL gain an opt-in mode (`NEPH_DEBUG=1` env var or `setup({ log = { file = "..." }})`) that writes log lines to a file as soon as they're emitted (vs. holding them in memory). Helps post-mortem when nvim is killed without a chance to dump state.
- **WATCHDOG (opt-in)**: a small `lua/neph/internal/watchdog.lua` that wraps key callbacks in a `vim.uv.hrtime` measurement and logs at WARN if any single call exceeds 200 ms. Cheap to leave on; goes silent in normal operation; gives us a bread-crumb trail when freezes happen.
- **AUDITED** every `vim.fn.system` call site in `lua/neph/` to confirm none remain in autocmd handlers, fs_watcher callbacks, or coroutine-resume paths. Document the audit in `design.md`.

## Capabilities

### Modified Capabilities

- `agent-lifecycle` — marks-based visual-selection capture for `<leader>ja`/`<leader>jc`.
- `review-ui` — popup review style with inline hunk rendering, per-agent override.
- `peer-adapter` — claudecode peer takes ownership of wezterm pane lifecycle when configured to spawn externally.

## Impact

### Lua plugin

- `lua/neph/api.lua` — `M.ask` / `M.comment` read `'<` and `'>` marks, pass through as `selection_marks` opts.
- `lua/neph/internal/input.lua` — accept `opts.selection_marks`, pass through to `context.from_marks` if present.
- `lua/neph/internal/context.lua` — new `M.from_marks(buf, marks)` constructor.
- `lua/neph/api/review/popup.lua` (NEW) — popup UI with inline hunks via `engine.compute_hunks`.
- `lua/neph/api/review/init.lua` — `set_open_fn` callback resolves `review_style` and dispatches to popup or `_open_immediate`.
- `lua/neph/config.lua` — adds `review.style` field; validates `"tab" | "popup"`.
- `lua/neph/internal/contracts.lua` — adds optional `review_style` field on AgentDef; also tightens validation for `peer.override_diff` / `peer.intercept_permissions` types (low-priority audit fix).
- `lua/neph/agents/claude-peer.lua` — sets `review_style = "popup"`.
- `lua/neph/agents/opencode-peer.lua` — sets `review_style = "popup"`.
- `lua/neph/peers/claudecode.lua` — exports `M.wezterm_pane_cmd` helper; rewrites `M.send`/`M.is_visible`/`M.focus`/`M.kill`/`M.hide` to use the tracked pane_id when present; registers VimLeavePre cleanup.

### User-facing config

- User's `~/.config/nvim/lua/plugins/claudecode.lua` migrates from inline wezterm-pane logic to `external_terminal_cmd = require("neph.peers.claudecode").wezterm_pane_cmd`. Functionally identical (same pane spawn, same orphan cleanup) but now neph owns the pane_id and can send text to it.

### Tests

- `tests/api/visual_selection_marks_spec.lua` (NEW) — keymap-callback simulation: marks set → `+selection` expands; marks unset → falls back to `+cursor`; block-mode marks expand correctly.
- `tests/api/review/popup_spec.lua` (NEW) — accept / reject / view / later paths; gate=bypass skips popup; gate=hold skips popup; snacks-absent fallback uses vim.ui.select; hunk rendering visible in window contents.
- `tests/peers/claudecode_wezterm_pane_spec.lua` (NEW) — `wezterm_pane_cmd` returns expected argv shape; pane_id captured asynchronously; `M.send` shells out to wezterm cli when pane_id present; falls back to chansend when not.
- `tests/agents_launch_args_spec.lua` and `tests/e2e/smoke_test.lua` — fix stale `require("neph.agents.claude")` to use `claude-peer`.

### CHANGELOG / docs

- README: document `review.style` and per-agent override; describe the popup with screenshot/ASCII; document the wezterm-pane integration including the `wezterm_pane_cmd` helper.
- CHANGELOG (Unreleased): bundle all four items under the `peer-diff-integration` follow-up section.
