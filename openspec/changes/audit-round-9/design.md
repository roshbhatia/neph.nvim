## Context

After 8 rounds of auditing, the codebase has solid foundations but a thorough E2E audit revealed 33 remaining issues. The most impactful cluster around review lifecycle robustness (graceful exit, agent crash recovery), resource leaks (timers, file descriptors, debounce handlers), and TypeScript connection lifecycle (pending requests, reconnect timers).

## Goals / Non-Goals

**Goals:**
- Ensure no data loss when Neovim exits during an active review
- Clean up orphaned review UI when an agent session dies
- Eliminate all identified timer and file descriptor leaks
- Harden RPC dispatch against invalid channel IDs
- Fix CLI hanging on fs.watch errors

**Non-Goals:**
- Adding new features or UX changes (separate change for manual review)
- Refactoring architecture — these are targeted fixes
- Addressing low-priority documentation gaps in protocol.json

## Decisions

**Review graceful exit:** Add a VimLeavePre autocmd in `review/init.lua` that checks for an active review session. If one exists, reject all undecided hunks with reason "Neovim exiting", finalize, and write the result. This ensures the waiting agent gets a response rather than timing out after 300s.

**Agent crash cleanup:** In `session.kill_session()`, after clearing the review queue for the agent, also call `ui.cleanup()` on any active review UI state. Track the active `ui_state` in a module-level variable in `review/init.lua` so it's accessible for forced cleanup.

**Debounce timer fix:** In `fs_watcher.watch_file()`, check for and stop any existing `debounce_timers[filepath]` before creating a new one. This prevents the orphaning that happens on rapid successive file changes.

**Buffer validity guards:** Add `vim.api.nvim_buf_is_valid(buf)` as the first check in every keymap callback in `ui.lua`, before checking `finalized`. This prevents accessing closure state after buffer wipe.

**RPC notify protection:** Wrap all `vim.rpcnotify()` calls in `api/ui.lua` with pcall. Invalid channel IDs from stale agent connections would otherwise crash Neovim.

**CLI watcher cleanup:** In `neph-cli/index.ts`, call `watcher.close()` in all exit paths (success, error, timeout). On `fs.watch` error, call cleanup and exit with code 1.

**NephClient disconnect hygiene:** In `disconnect()`, clear `reconnectTimer` and reject+clear all `pendingRequests`. In `_scheduleReconnect()`, check `disconnected` flag before each attempt.

**Symlink validation:** Use `vim.fn.resolve()` on both source and destination before prefix-matching validation in `tools.lua`.

**Falsy config values:** Use `cfg.interval ~= nil and cfg.interval or 1000` pattern instead of `cfg.interval or 1000` to allow zero values.

## Risks / Trade-offs

- **VimLeavePre finalization** adds a synchronous step to Neovim exit. If the result file write is slow (network filesystem), exit could be delayed. Mitigated by the write being to a local temp file.
- **Forced review cleanup on agent kill** could lose user decisions if they were still actively reviewing. Acceptable because the agent is already dead — the review has no consumer.
- **Buffer validity check** adds a small overhead per keymap invocation. Negligible for human-speed interactions.
