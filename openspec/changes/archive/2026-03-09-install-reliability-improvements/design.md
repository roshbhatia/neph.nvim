## Context

The current install system in `lua/neph/tools.lua` uses git HEAD hashes as version stamps stored in `~/.local/share/nvim/neph_install_<agent>.stamp`. This approach has several weaknesses:
- Misses changes during local development (git HEAD unchanged but source modified)
- Silent failures leave partially installed tools
- No transaction rollback on mid-install failures
- pi extension connection errors surface opaquely in logs

The pi extension (`tools/pi/pi.ts`) uses NephClient with basic exponential backoff but lacks jitter, explicit state management, and graceful degradation.

Users hit these issues during:
- Plugin updates (stale builds not detected)
- Local development (source changes don't trigger rebuild)
- Network hiccups (pi disconnects and retries aggressively)

## Goals / Non-Goals

**Goals:**
- Content-based fingerprinting that catches all source changes (SHA256 per file)
- Atomic install transactions with rollback on failure
- Pre-flight and post-install verification
- Pi extension connection resilience with jitter and state tracking
- Actionable error messages with remediation steps
- Enhanced health check diagnostics

**Non-Goals:**
- Distributed install coordination (single Neovim instance only)
- Cross-platform symlink alternatives (users must have `ln -s`)
- GUI install progress (terminal notifications sufficient)
- Hot reload of extension code (requires pi restart)

## Decisions

### Decision 1: SHA256 manifest replaces stamp files

**Rationale:** Content hashing detects all changes (git or local edits). Use SHA256 of source files to create fingerprint, store in JSON manifest at `~/.local/state/neph/fingerprints.json`.

**Manifest structure:**
```json
{
  "neph-cli": {
    "sources": {
      "tools/neph-cli/src/index.ts": "abc123...",
      "tools/neph-cli/src/transport.ts": "def456..."
    },
    "artifacts": {
      "tools/neph-cli/dist/index.js": "ghi789..."
    }
  },
  "pi": { ... }
}
```

**Why SHA256 over mtime:** Mtime can be unreliable (git checkout, filesystem sync), SHA256 is deterministic.

**Alternatives considered:**
- Keep git HEAD + add mtime check: Still misses cases where checkout happens but files identical
- Use CRC32: Faster but collision risk in large codebases

### Decision 2: Transaction log per agent

**Rationale:** Each agent install is independent transaction. Use JSON log at `~/.local/state/neph/transactions/<agent>.json` tracking operations in progress.

**Log structure:**
```json
{
  "agent": "pi",
  "started": 1234567890,
  "operations": [
    { "type": "symlink", "src": "...", "dst": "...", "backup": null },
    { "type": "merge", "dst": "...", "backup": "/tmp/neph-backup-..." }
  ],
  "status": "in_progress"
}
```

**Rollback logic:** On failure or incomplete transaction at startup:
1. Restore backups for merges
2. Remove symlinks created in this transaction
3. Mark transaction as "rolled_back"

**Why per-agent isolation:** One agent failure shouldn't block others. Claude can work while pi install fails.

**Alternatives considered:**
- Single global transaction: More complex, worse failure isolation
- No rollback: Leaves broken state

### Decision 3: Verification as separate phase

**Rationale:** Separate pre-flight (check dependencies) and post-install (validate artifacts) phases.

**Pre-flight checks:**
- `vim.fn.executable("node") == 1`
- `vim.fn.executable("npm") == 1`

**Post-install validation:**
- Symlinks: `vim.uv.fs_stat(dst)` succeeds
- Builds: Expected artifact path exists and is readable
- Merges: Destination JSON parses successfully

**Why separate phases:** Clear failure attribution. Pre-flight fails = env issue. Post-install fails = bug in install logic.

**Alternatives considered:**
- Validation during operation: Harder to rollback mid-stream
- No pre-flight: Waste time running partial install before failing

### Decision 4: Exponential backoff with full jitter

**Rationale:** pi extension reconnect should avoid thundering herd. Use full jitter: `delay = random(0, min(cap, base * 2^attempt))`.

**Parameters:**
- Base: 100ms
- Cap: 5000ms
- Max attempts: unlimited (until manual disconnect)

**Connection state machine:**
```
disconnected → connecting → connected
     ↑              ↓
     └──reconnecting←┘
```

**Why full jitter over decorrelated:** Simpler, proven effective (AWS blog post), no correlation tracking needed.

**Alternatives considered:**
- Fixed retry intervals: Thundering herd risk
- Exponential without jitter: Multiple instances sync up
- Circuit breaker pattern: Overkill for single client

### Decision 5: Structured error results

**Rationale:** All install operations return `{ ok: boolean, error?: { code, message, remedy } }`. Health check and status output consume these.

**Error codes:**
- `EPERM`: Permission denied
- `ENOENT`: File not found
- `BUILD_FAILED`: npm build error
- `VALIDATION_FAILED`: Post-install check failed
- `ECONNREFUSED`: Socket connection failed

**Remedy examples:**
- `EPERM` → "Ensure <dir> is writable or run with sudo"
- `BUILD_FAILED` → "Check package.json and run npm install manually"
- `ECONNREFUSED` → "Ensure Neovim is running with $NVIM_SOCKET_PATH set"

**Why structured:** Enables programmatic error handling, consistent UX, easier testing.

**Alternatives considered:**
- String errors: Harder to parse programmatically
- Just error codes: No user-friendly message

## Risks / Trade-offs

### Risk: SHA256 hashing performance on large source trees
- **Mitigation:** Hash only source files in `src_dirs` array (typically <50 files per agent). Cache in manifest, only recompute on mtime change.

### Risk: Transaction log corruption leaves broken state
- **Mitigation:** Write to `.tmp` file, atomic rename. If corruption detected, delete log and run full reinstall.

### Risk: Reconnect storms if multiple pi instances
- **Mitigation:** Full jitter spreads reconnects. Document single-instance expectation in agent def.

### Risk: Backup files accumulate over time
- **Mitigation:** Timestamp backups, add cleanup task to remove backups >7 days old on install.

### Risk: Verification phase adds install latency
- **Mitigation:** Run validations in parallel using `vim.fn.jobstart`. Expect <500ms overhead.

### Trade-off: Fingerprint manifest size grows with file count
- **Acceptable:** JSON gzips well, expect <10KB even with 500+ files tracked.

### Trade-off: Rollback can't undo npm side effects
- **Acceptable:** `node_modules/` directories outside transaction scope. Document "reinstall from scratch" escape hatch.

## Migration Plan

**Phase 1: Deploy fingerprinting (backward-compatible)**
1. Keep stamp files alongside new manifest
2. If stamp missing or manifest missing, run full install
3. Populate manifest on successful install
4. Log warning if stamp/manifest disagree

**Phase 2: Enable transactions**
1. Transaction logs start empty (no rollback on first run)
2. Future installs use transaction system
3. Detect incomplete transactions at startup, notify user

**Phase 3: Remove stamp files**
1. After 2 releases, delete stamp logic
2. Migrate remaining stamp-only users via warning in health check

**Rollback strategy:** If critical bug in fingerprinting:
1. Tag release before migration
2. Document downgrade steps (delete manifest, reinstall)
3. Fix forward in patch release

## Open Questions

1. **Should fingerprinting extend to git submodules?**
   - Lean toward no: neph has no submodules, defer until needed

2. **Verification timeout values?**
   - Start with 30s for builds, 5s for symlink checks. Tune based on telemetry.

3. **Expose transaction log via RPC for debugging?**
   - Nice-to-have. Defer to future if users request it.

4. **Should pi reconnect give up after N failures?**
   - Current decision: retry forever (user can manually disconnect). Revisit if feedback suggests timeout needed.
