## Why

An end-to-end audit of the codebase revealed 34 issues across error handling, race conditions, security, testing gaps, and spec compliance. Several are crash-inducing nil dereferences or silent data-loss bugs in the review pipeline and session lifecycle. Addressing these hardens the plugin for real-world use where agents fire writes rapidly and concurrently.

## What Changes

- **Nil guards**: Add missing nil checks in `review/init.lua` (write_result path), `session.lua` (agent nil before companion check), `fs_watcher.lua` (io.open guard)
- **Error propagation**: Check `os.rename()` return values in `tools.lua` (5 call sites), log bus health-check failures, surface `launch_args_fn` errors at WARN level
- **Race condition fixes**: Guard companion respawn against killed sessions, fix debounce timer accumulation in fs_watcher, prevent file_refresh timer leak on double setup
- **Security hardening**: Validate expanded `sym_spec.dst` stays within project root, shellescape all git command paths in `placeholders.lua`
- **Config surface**: Make `MAX_WATCHED`, companion `DEBOUNCE_MS`, and `file_refresh` timer interval configurable with current values as defaults
- **Testing**: Add tests for nil-path write_result, fs_watcher file-deleted race, session.send with cleared pane_id, companion orphan respawn, review.pending dispatch
- **Spec compliance**: Update agent-bus health check timing, add socket-integration README section, fix stale `tools/core/lua/` reference in spec
- **Cleanup**: Remove dead `agents/all.lua` if unused, add `cancel_path()` to review queue, add `get_watches()` to fs_watcher for debugging

## Capabilities

### New Capabilities

_(none — all fixes are to existing modules)_

### Modified Capabilities

- `review-queue`: Add `cancel_path(path)` API for cancelling a queued review by file path
- `fs-watcher-review`: Add configurable `max_watched`, add `get_watches()` debug API, fix file-deleted crash
- `review-protocol`: Guard `write_result()` against nil result_path
- `review-pending-feedback`: No spec-level change (implementation fix only)
- `resource-lifecycle`: Fix companion orphan respawn, file_refresh timer leak, debounce timer accumulation
- `tool-install`: Check `os.rename()` return values, validate symlink destination paths
- `socket-integration`: Add README documentation section per spec requirement
- `agent-bus`: Fix health-check failure logging

## Impact

- **Lua source**: `api/review/init.lua`, `internal/session.lua`, `internal/fs_watcher.lua`, `internal/companion.lua`, `internal/file_refresh.lua`, `internal/bus.lua`, `internal/placeholders.lua`, `tools.lua`, `config.lua`, `init.lua`
- **Tests**: New test files or additions to `review_queue_spec`, `fs_watcher_spec`, `session_spec`, `rpc_spec`
- **Specs**: Delta specs for 8 existing capabilities
- **Docs**: README.md gains Socket Integration section
- **No breaking changes** — all fixes are additive or internal
