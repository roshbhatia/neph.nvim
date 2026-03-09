## Why

The current install process has reliability issues: stamp-based versioning can miss changes during local development, install failures are partially silent, and the pi extension lacks robust error recovery. Users encounter broken symlinks, stale builds, and unclear failure states. We need a bulletproof install system and rock-solid pi integration that leverages neph's full feature set (bus, review, status management).

## What Changes

- Replace git-hash stamp system with content-based fingerprinting (per-file hashing for builds/symlinks)
- Add comprehensive install verification (pre-flight checks, post-install validation, health integration)
- Implement automatic repair on version mismatch detection (self-healing on startup)
- Make pi extension connection more robust (exponential backoff with jitter, explicit connection lifecycle)
- Add pi extension health monitoring (bus heartbeat, connection status reporting)
- Improve error surfacing (structured install results, actionable error messages, `--verbose` flag)
- Add install transaction system (atomic operations, rollback on partial failure)
- Enhance :NephTools status output (colored status indicators, detailed diagnostics)

## Capabilities

### New Capabilities
- `install-fingerprinting`: Content-based fingerprinting system for tracking build artifacts and symlink targets (replaces stamp versioning)
- `install-verification`: Pre-flight checks and post-install validation ensuring all tools are functional before declaring success
- `install-transactions`: Atomic install operations with rollback capability when operations fail mid-stream
- `pi-connection-resilience`: Robust connection lifecycle management for pi extension with exponential backoff, jitter, and health monitoring
- `install-diagnostics`: Enhanced error reporting and diagnostics for install/build failures with actionable remediation steps

### Modified Capabilities
<!-- No existing specs being modified - this is net-new reliability infrastructure -->

## Impact

**Code affected:**
- `lua/neph/tools.lua` — fingerprinting, verification, transaction system
- `lua/neph/init.lua` — auto-repair on startup
- `lua/neph/health.lua` — enhanced diagnostics integration
- `tools/lib/neph-client.ts` — improved reconnection logic with jitter
- `tools/pi/pi.ts` — connection lifecycle management
- `tests/e2e/tools_test.lua` — updated validation tests

**New dependencies:**
- None (pure Lua/TypeScript implementation using stdlib)

**User-facing changes:**
- More reliable first-run experience (auto-repair)
- Clearer error messages with remediation steps
- `:NephTools status` shows detailed diagnostic info
- `:checkhealth neph` provides deeper validation
