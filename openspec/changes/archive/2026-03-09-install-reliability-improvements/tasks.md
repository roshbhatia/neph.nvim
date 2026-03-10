## 1. Fingerprinting System

- [x] 1.1 Create fingerprint manifest path at `~/.local/state/neph/fingerprints.json`
- [x] 1.2 Add SHA256 helper function using `vim.fn.sha256()` for file hashing
- [x] 1.3 Implement `compute_fingerprint(root, agent)` returning { sources: {path: hash}, artifacts: {path: hash} }
- [x] 1.4 Implement `load_manifest()` reading JSON from disk (handle missing file)
- [x] 1.5 Implement `save_manifest(data)` with atomic write (tmp + rename)
- [x] 1.6 Implement `is_agent_current(manifest, root, agent)` comparing stored vs computed hashes
- [x] 1.7 Update `is_agent_up_to_date()` to use fingerprint instead of stamp
- [x] 1.8 Keep backward-compat: if stamp exists but manifest missing, migrate stamp to manifest
- [x] 1.9 Add unit tests for fingerprinting logic (hash computation, manifest I/O)

## 2. Verification Phase

- [x] 2.1 Implement `preflight_checks()` validating node and npm are on PATH
- [x] 2.2 Implement `verify_symlink(src, dst)` returning detailed status (ok/broken/wrong_target/missing)
- [x] 2.3 Implement `verify_build(root, build_spec)` checking artifact exists and is readable
- [x] 2.4 Implement `verify_merge(dst)` validating JSON is parseable
- [x] 2.5 Implement `postinstall_validate(root, agent)` running all verifications for an agent
- [x] 2.6 Add structured result type: `{ ok: bool, error?: { code, message, remedy } }`
- [ ] 2.7 Update install functions to return structured results
- [ ] 2.8 Add unit tests for verification functions (mocked file states)

## 3. Transaction System

- [x] 3.1 Create transaction log directory at `~/.local/state/neph/transactions/`
- [x] 3.2 Implement `begin_transaction(agent)` creating log file with started timestamp
- [x] 3.3 Implement `log_operation(agent, op)` appending operation to transaction log
- [x] 3.4 Implement `commit_transaction(agent)` marking status as "complete"
- [x] 3.5 Implement `rollback_transaction(agent, log)` reversing operations (restore backups, remove symlinks)
- [ ] 3.6 Update `install_symlink()` to log operation and create backup if overwriting
- [ ] 3.7 Update `json_merge()` to create timestamped backup before merge
- [x] 3.8 Implement `detect_incomplete_transactions()` at startup checking for "in_progress" logs
- [ ] 3.9 Add auto-rollback on startup for incomplete transactions (notify user)
- [ ] 3.10 Add unit tests for transaction operations (rollback scenarios)

## 4. Enhanced Error Reporting

- [x] 4.1 Define error code constants (EPERM, ENOENT, BUILD_FAILED, VALIDATION_FAILED, ECONNREFUSED)
- [x] 4.2 Implement `make_error(code, message, remedy)` helper
- [ ] 4.3 Update all install operations to use structured errors
- [ ] 4.4 Implement `:NephTools status --verbose` flag parsing
- [ ] 4.5 Enhance `:NephTools status` output with color-coded indicators (use vim.health helpers)
- [ ] 4.6 Add staleness detection to status output (compare source vs artifact mtimes)
- [ ] 4.7 Update `health.lua` to consume structured errors and show remediation steps
- [ ] 4.8 Add debug log entries for verbose mode (log each install operation)

## 5. Pi Connection Resilience (TypeScript)

- [x] 5.1 Add jitter helper: `fullJitter(base, attempt, cap)` returning randomized delay
- [x] 5.2 Update `_scheduleReconnect()` to use full jitter (0 to min(cap, base * 2^attempt))
- [x] 5.3 Add connection state enum: DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING
- [x] 5.4 Expose `getConnectionState()` method on NephClient
- [x] 5.5 Update connection event logging to include state transitions
- [ ] 5.6 Implement review operation queueing when disconnected (with 30s timeout)
- [ ] 5.7 Add unit tests for reconnection logic (mocked socket disconnect scenarios)
- [ ] 5.8 Add unit tests for jitter distribution (verify randomness bounds)

## 6. Pi Health Monitoring (Lua)

- [ ] 6.1 Update bus heartbeat timer to log connection state changes
- [ ] 6.2 Add `vim.g.pi_connection_state` global updated by bus heartbeat
- [ ] 6.3 Update `health.lua` to show pi connection state if pi is registered
- [ ] 6.4 Add bus reconnection counter (track how many times agent reconnected)
- [ ] 6.5 Surface reconnection count in health check output

## 7. Auto-Repair on Startup

- [ ] 7.1 Update `init.lua` to call `detect_incomplete_transactions()` on setup
- [ ] 7.2 Implement `auto_repair()` that runs install for stale agents (fingerprint mismatch)
- [ ] 7.3 Add config option `auto_repair = true` (default enabled)
- [ ] 7.4 Show notification on auto-repair trigger: "Neph: auto-repairing <agent> tools"
- [ ] 7.5 Add unit test for auto-repair (mock stale fingerprint)

## 8. Integration Testing

- [ ] 8.1 Update `tests/e2e/tools_test.lua` to verify fingerprint manifest creation
- [ ] 8.2 Add e2e test for transaction rollback (simulate install failure mid-stream)
- [ ] 8.3 Add e2e test for pre-flight check failure (mock missing node binary)
- [ ] 8.4 Add e2e test for post-install validation catching broken symlink
- [ ] 8.5 Add integration test for pi reconnection (kill socket, verify reconnect)
- [ ] 8.6 Update CI to run full test suite including new e2e tests

## 9. Documentation

- [ ] 9.1 Update README.md with troubleshooting section (common errors + remediation)
- [ ] 9.2 Add fingerprinting section to AGENTS.md (explain manifest system)
- [ ] 9.3 Document `:NephTools status --verbose` flag in vimdoc
- [ ] 9.4 Add "Auto-repair" section to vimdoc explaining startup behavior
- [ ] 9.5 Regenerate vimdoc with `task docs`

## 10. Cleanup and Migration

- [ ] 10.1 Add deprecation notice for stamp files (log warning if stamp exists)
- [ ] 10.2 Implement automatic stamp-to-manifest migration on first run
- [ ] 10.3 Add cleanup task to remove backup files older than 7 days
- [ ] 10.4 Remove stamp file logic after 2 releases (schedule for future)
