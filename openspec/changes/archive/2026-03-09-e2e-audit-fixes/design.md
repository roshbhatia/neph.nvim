## Context

An end-to-end audit identified 34 issues across error handling, race conditions, security, testing, and spec compliance. The codebase is well-structured but has gaps in defensive coding — nil guards, unchecked return values, silent failures, and timer lifecycle bugs. These are all internal fixes; no public API changes.

## Goals / Non-Goals

**Goals:**
- Fix all crash-inducing nil dereferences (review write_result, session companion check, fs_watcher io.open)
- Add error propagation for os.rename() in tools.lua (5 sites)
- Fix 3 race conditions (companion orphan respawn, debounce timer accumulation, file_refresh double-setup)
- Harden security (path traversal validation, shellescape git paths)
- Make 3 hardcoded constants configurable (MAX_WATCHED, companion DEBOUNCE_MS, file_refresh interval)
- Add missing tests for nil-path, file-deleted race, send-with-cleared-pane, companion orphan
- Fix spec compliance gaps (bus health check logging, socket-integration README, stale spec reference)
- Add cancel_path() and get_watches() APIs for completeness

**Non-Goals:**
- Rewriting any module's architecture
- Changing the public API surface
- Adding new agent integrations
- Performance optimization beyond fixing O(n) concerns flagged in audit

## Decisions

### 1. Nil guards: early-return pattern
Add `if not x then return end` at the top of affected functions rather than wrapping entire bodies in conditionals. Consistent with existing codebase style (e.g., session.lua:197).

**Alternative considered:** pcall wrapping — rejected because it hides the error entirely, whereas early-return is explicit and debuggable.

### 2. os.rename error handling: log + return false
Wrap os.rename calls with `local ok, err = os.rename(...)` and log at WARN level on failure. Return false from the enclosing function to let callers decide how to handle it.

**Alternative considered:** error() on failure — rejected because tools.lua runs during setup and throwing would break plugin load.

### 3. Companion respawn guard: check vim.g before respawn
Before the 2s deferred respawn in companion.lua, check `vim.g.gemini_active`. If nil, skip respawn. Simple, no new state needed.

### 4. Debounce timer fix: stop+close before creating new
In fs_watcher.lua, before creating a new debounce timer for a path, check if one exists and stop+close it first. Prevents accumulation.

### 5. file_refresh double-setup fix: idempotent teardown
Call M.teardown() at the top of M.setup() so double-setup is safe. teardown() already exists and is idempotent.

### 6. Config additions: nest under existing review config
Add `review.fs_watcher.max_watched` (default 100), `review.companion_debounce_ms` (default 50), `file_refresh.interval` (default 1000). All optional with current hardcoded values as defaults.

### 7. Path traversal: validate resolved path starts with project root
In init.lua, after `vim.fn.expand(sym_spec.dst)`, check that the resolved absolute path starts with the project root or `vim.env.HOME`. Reject otherwise.

### 8. Shellescape: wrap path in placeholders.lua git diff
Single fix: `vim.fn.shellescape(rel)` around the path argument in the git diff command.

### 9. README socket section: minimal addition
Add a "Socket Integration" section to README.md explaining NVIM_SOCKET_PATH. Also fix stale `tools/core/lua/` reference in the socket-integration spec to match actual path.

### 10. Bus health check logging: add log.debug on failure
Change the pcall in bus health check to capture the error and log it via `log.debug("bus", ...)`. Does not change timing behavior.

### 11. Dead code: verify agents/all.lua usage before removing
grep for requires of `neph.agents.all` — if none found, delete the file.

## Risks / Trade-offs

- [Early-return nil guards may mask deeper bugs] → Mitigated by logging at debug level when returning early, so issues are discoverable
- [Config additions increase surface area] → Mitigated by keeping all new config keys optional with safe defaults identical to current hardcoded values
- [README changes may conflict with in-flight docs work] → Low risk, section is additive
- [Removing agents/all.lua if it's dynamically loaded] → Mitigated by grepping for both string and require patterns before deleting
