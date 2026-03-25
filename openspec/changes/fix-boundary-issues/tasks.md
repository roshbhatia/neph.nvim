## 1. Fix bus race conditions

- [x] 1.1 Fix bus health timer iteration safety in `lua/neph/internal/bus.lua`
  - Modify `_ensure_health_timer` to collect dead channels first, unregister after iteration
  - Add test for concurrent registration/unregistration during health checks

- [x] 1.2 Add bus health monitoring tests in `tests/bus_spec.lua`
  - Test health timer starts/stops based on channel count
  - Test dead channel detection and cleanup
  - Test iteration safety with multiple concurrent channels

## 2. Fix review queue concurrency

- [x] 2.1 Add reentrancy protection to `lua/neph/internal/review_queue.lua`
  - Add processing flag to prevent concurrent state modifications
  - Use `vim.schedule` for retry when busy

- [x] 2.2 Add concurrency tests for review queue
  - Test concurrent enqueue operations
  - Test state consistency under rapid operations
  - Test cancellation during active processing

## 3. Align CLI and extension agent reliability

- [x] 3.1 Update `tools/lib/neph-client.ts` review method
  - Add `result_path` parameter to extension agent review calls
  - Generate temp file path with UUID like CLI does
  - Maintain backward compatibility (parameter optional in Lua)

- [ ] 3.2 Update Lua `review.open` to handle optional result_path for extensions
  - Ensure `write_result` handles nil result_path gracefully
  - Verify both notification and file write paths work

- [x] 3.3 Add tests for unified result_path handling
  - Test CLI agent with result_path fallback
  - Test extension agent with result_path fallback
  - Test notification failure recovery for both agent types

## 4. Complete protocol validation

- [x] 4.1 Update `tools/neph-cli/tests/contract.test.ts`
  - Add missing methods: `status.get`, `bus.register`, `review.pending`
  - Verify all 11 methods from protocol.json are tested
  - Add test for parameter list validation

- [x] 4.2 Verify Lua contract test completeness
  - Ensure `tests/contract_spec.lua` validates all methods
  - Add any missing method validations

## 5. Add missing boundary tests

- [x] 5.1 Create `tests/bus_health_spec.lua` for bus health monitoring
  - Test timer lifecycle (start/stop)
  - Test dead channel cleanup
  - Test concurrent operations safety

- [x] 5.2 Create `tests/review_queue_concurrency_spec.lua`
  - Test concurrent enqueue/dequeue
  - Test atomic state transitions
  - Test error recovery during concurrent operations

- [x] 5.3 Update `tools/neph-cli/tests/transport.test.ts`
  - Add tests for socket discovery edge cases
  - Test monorepo scenarios with heuristic scoring
  - Test fallback behavior for ambiguous cases

- [ ] 5.4 Create integration tests for end-to-end workflows (skip for now)
  - CLI → Neovim → Review → Result flow
  - Extension agent registration → prompt delivery → review cycle
  - Multiple agent concurrent operation

## 6. Improve socket discovery

- [x] 6.1 Enhance `tools/neph-cli/src/transport.ts` socket discovery
  - Implement heuristic scoring for monorepo cases
  - Add directory depth matching for closest cwd
  - Maintain conservative fallback (return null on true ambiguity)

- [x] 6.2 Add tests for socket discovery improvements
  - Test monorepo scenario scoring
  - Test fallback when no clear match
  - Test cross-platform path patterns

## 7. Fix temporary file cleanup

- [ ] 7.1 Improve file cleanup in `tools/neph-cli/src/index.ts`
  - Add retry with exponential backoff for file deletion
  - Handle "file busy" errors gracefully
  - Add cleanup of orphaned .tmp files on startup

- [ ] 7.2 Add atomic file write improvements in `lua/neph/api/review/init.lua`
  - Ensure .tmp file cleanup on write failure
  - Add file locking or rename atomicity guarantees

## 8. Improve state synchronization

- [ ] 8.1 Validate bus channels against agent sessions
  - Add consistency check between bus channels and session state
  - Log warnings when mismatches detected

- [ ] 8.2 Add locking for shared state in Lua modules
  - Review all global state access patterns
  - Add protection for `active_review` variable in review system
  - Ensure thread-safe operations in single-threaded async environment

## 9. Add comprehensive error recovery tests

- [ ] 9.1 Create `tests/error_recovery_spec.lua`
  - Test Neovim crash/reconnect scenarios
  - Test file system edge cases (symlinks, permissions, full disks)
  - Test network filesystem timeouts and errors

- [ ] 9.2 Update existing tests for error paths
  - Ensure all error conditions in bus, review, and transport are tested
  - Add tests for graceful degradation and recovery

## 10. Run full test suite and verify fixes

- [ ] 10.1 Run Lua test suite: `task test:lua`
  - Verify all new tests pass
  - Ensure no regressions in existing tests

- [ ] 10.2 Run TypeScript test suite: `task test:cli` and `task test:pi`
  - Verify contract tests pass with all methods
  - Ensure transport tests pass with new socket discovery

- [ ] 10.3 Run linting: `task lint`
  - Ensure code style consistency
  - Fix any linting issues introduced

- [ ] 10.4 Run full CI pipeline: `task ci`
  - Verify all tests pass in Dagger environment
  - Ensure no integration issues