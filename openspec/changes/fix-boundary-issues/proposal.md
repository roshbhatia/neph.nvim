## Why

Multiple boundary issues and testing gaps were discovered that threaten the reliability of neph.nvim, especially in multi-agent scenarios and production usage. The plugin currently has race conditions in core subsystems, asymmetric error handling between CLI and extension agents, incomplete protocol validation, and critical testing gaps at system boundaries.

These issues could cause data loss (lost review results), system crashes (race conditions in bus), and silent failures (missing protocol validation). Fixing these now prevents production incidents and establishes a foundation for robust multi-agent workflows.

## What Changes

- **Fix race conditions in bus system**: Modify bus.lua health timer to avoid modifying channels table while iterating
- **Fix review queue concurrency**: Add mutex or atomic operations to prevent state corruption
- **Align CLI and extension agent reliability**: Ensure both agent types use result_path fallback for reviews
- **Complete protocol contract validation**: Update TypeScript tests to match all methods in protocol.json
- **Add missing boundary tests**: Create comprehensive tests for bus health monitoring, review queue concurrency, and socket discovery edge cases
- **Improve socket discovery**: Handle monorepo cases better while maintaining conservative defaults
- **Fix temporary file cleanup**: Add proper locking and error handling
- **Improve state synchronization**: Validate bus channels against agent sessions and add locking for shared state

**BREAKING**: No breaking changes - all fixes maintain backward compatibility.

## Capabilities

### New Capabilities
- `boundary-reliability`: Ensure reliable operation across system boundaries (RPC, CLI, extension agents)
- `boundary-testing`: Comprehensive test coverage for boundary interactions and edge cases
- `concurrency-safety`: Thread-safe operations in Lua single-threaded async environment
- `error-handling-symmetry`: Consistent error handling patterns across all agent types

### Modified Capabilities
- `protocol-contract`: Update TypeScript contract tests to validate all methods
- `socket-discovery`: Improve handling of ambiguous socket discovery cases
- `review-system`: Enhance reliability with result_path fallback for all agent types
- `agent-bus`: Fix race conditions and improve health monitoring

## Impact

**Affected code:**
- `lua/neph/internal/bus.lua` - Health timer iteration fix
- `lua/neph/internal/review_queue.lua` - Concurrency fixes
- `lua/neph/api/review/init.lua` - Result path handling unification
- `tools/neph-cli/tests/contract.test.ts` - Protocol validation updates
- `tools/lib/neph-client.ts` - Review method parameter alignment
- `tools/neph-cli/src/transport.ts` - Socket discovery improvements
- `tests/bus_spec.lua` - New health monitoring tests
- Multiple new test files for boundary coverage

**APIs:** No API changes, all fixes internal
**Dependencies:** No new dependencies
**Systems:** Improved reliability for multi-agent workflows and production usage