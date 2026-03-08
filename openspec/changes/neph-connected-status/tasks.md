## Tasks

### Task 1: Add neph_connected to gate.ts

**Files:** `tools/neph-cli/src/gate.ts`

- In `runGate()`, after transport connection succeeds:
  - Call `transport.executeLua(RPC_CALL, ['status.set', { name: 'neph_connected', value: 'true' }])`
- In `cleanup()`, before `transport.close()`:
  - Call `transport.executeLua(RPC_CALL, ['status.unset', { name: 'neph_connected' }])`
- In cursor post-write path: same set/unset around the checktime block
- When transport is null (no socket): skip `neph_connected` calls (fail-open)

### Task 2: Add neph_connected to review command (index.ts)

**Files:** `tools/neph-cli/src/index.ts`

- In the review command handler, after transport connection:
  - Set `neph_connected`
- In cleanup:
  - Unset `neph_connected`

### Task 3: Add tests

**Files:** `tools/neph-cli/tests/gate.test.ts`, `tools/neph-cli/tests/commands.test.ts`

- gate.test.ts:
  - Verify `neph_connected` status.set is called during gate flow
  - Verify `neph_connected` status.unset is called in cleanup
  - Verify cursor path sets/unsets `neph_connected`
  - Verify no `neph_connected` call when transport is null
- commands.test.ts:
  - Verify review command sets/unsets `neph_connected`

### Task 4: Run full test suite

- `task test` — all Lua + TS tests pass
- `task tools:test` — all tool tests pass
