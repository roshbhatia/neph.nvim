## Why

Comprehensive E2E audit of the codebase revealed 33 issues across error handling, race conditions, resource leaks, robustness, and TypeScript connection lifecycle. Several are high-severity: review results are silently lost when Neovim exits mid-review, agent crash leaves orphaned review UI, debounce timers leak on rapid file changes, and the CLI hangs indefinitely on fs.watch errors. These issues affect reliability in real multi-agent workflows.

## What Changes

- Guard review UI keymap callbacks with `nvim_buf_is_valid(buf)` check to prevent stale state access
- Add VimLeavePre hook to finalize any active review (writes result before Neovim exits)
- Clean up orphaned review UI when agent session is killed
- Fix debounce timer orphaning in fs_watcher (clean old timer before creating new one)
- Wrap `vim.rpcnotify()` calls in `api/ui.lua` with pcall (invalid channel_id protection)
- Check `f:write()` return in review result writing
- Stop ready_timers in snacks backend `cleanup_all()`
- Clear pending retry timers in `session.kill_session()`
- Close file watcher on successful review completion in CLI (`neph-cli/index.ts`)
- Clear `pendingRequests` on NephClient disconnect
- Clear reconnect timer on explicit `disconnect()` in neph-client.ts
- Handle fs.watch errors in CLI by calling cleanup and exiting
- Fix `interval = 0` config override (falsy value handling in file_refresh)
- Resolve symlink destinations before validating paths in tools.lua

## Capabilities

### New Capabilities

- `review-graceful-exit`: Behavior when Neovim exits or agent crashes during an active review — finalization, cleanup, and result delivery guarantees

### Modified Capabilities

- `review-ui`: Guard callbacks against invalid buffer state, clean up autocmds properly
- `resource-lifecycle`: Timer and autocmd cleanup in snacks backend, session teardown, fs_watcher debounce
- `neph-cli`: File watcher leak fix, fs.watch error handling
- `agent-client-sdk`: Pending request cleanup on disconnect, reconnect timer clearing
- `tool-install`: Symlink path validation with resolved paths
- `rpc-dispatch`: pcall-wrap vim.rpcnotify for invalid channel protection

## Impact

- **Lua**: `api/review/ui.lua`, `api/review/init.lua`, `api/ui.lua`, `internal/fs_watcher.lua`, `internal/session.lua`, `internal/file_refresh.lua`, `backends/snacks.lua`, `tools.lua`, `init.lua`
- **TypeScript**: `tools/neph-cli/src/index.ts`, `tools/lib/neph-client.ts`
- **Tests**: New tests for graceful exit, debounce cleanup, pending request clearing
