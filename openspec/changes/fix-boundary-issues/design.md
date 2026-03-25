## Context

The neph.nvim plugin has several boundary issues discovered during exploration:
1. Race conditions in bus health timer (modifying table while iterating)
2. Concurrency issues in review queue (multiple agents can corrupt state)
3. Asymmetric error handling between CLI and extension agents (CLI has file fallback, extensions don't)
4. Incomplete protocol validation (TypeScript tests missing 3 methods)
5. Missing critical tests for boundary interactions and edge cases
6. Socket discovery ambiguity in monorepo setups
7. File cleanup race conditions

These issues exist at the boundaries between subsystems: Lua  TypeScript, CLI  extension agents, RPC protocol, and concurrent operations in a single-threaded async environment.

## Goals / Non-Goals

**Goals:**
1. Eliminate race conditions in core subsystems (bus, review queue)
2. Ensure consistent reliability across all agent types (CLI and extensions)
3. Complete protocol validation to catch contract mismatches early
4. Add comprehensive test coverage for boundary interactions
5. Improve error recovery and state synchronization
6. Maintain backward compatibility - no breaking changes

**Non-Goals:**
1. Redesign the architecture or introduce new abstractions
2. Change public APIs or configuration interfaces
3. Add new dependencies or major features
4. Over-optimize performance at expense of correctness
5. Handle all possible edge cases (focus on critical reliability issues)

## Decisions

**1. Fix bus race condition with two-pass approach**
- **Decision**: Collect dead channels first, then unregister after iteration
- **Rationale**: Simple, maintains existing API, avoids complex locking in Lua single-threaded environment
- **Alternative considered**: Using a copy of the table for iteration - less efficient for large channel counts
- **Implementation**: 
  ```lua
  local dead = {}
  for name, ch in pairs(channels) do
    local ok = pcall(vim.rpcnotify, ch, "neph:ping")
    if not ok then
      table.insert(dead, name)
    end
  end
  for _, name in ipairs(dead) do
    M.unregister(name)
  end
  ```

**2. Review queue concurrency with Lua coroutine-based mutex**
- **Decision**: Use a simple flag-based "mutex" since Lua is single-threaded
- **Rationale**: `vim.schedule` creates async execution but still single-threaded; flag prevents reentrancy
- **Alternative considered**: Queue of promises - overcomplicated for current usage patterns
- **Implementation**: 
  ```lua
  local processing = false
  function M.enqueue(params)
    if processing then
      -- Schedule retry
      vim.schedule(function() M.enqueue(params) end)
      return
    end
    processing = true
    -- ... existing logic ...
    processing = false
  end
  ```

**3. Unified result_path for all agent types**
- **Decision**: Extend extension agent review call to include result_path parameter
- **Rationale**: Provides file fallback for notification failures, matches CLI behavior
- **Alternative considered**: Keep asymmetry but add retry logic - less reliable than file fallback
- **Implementation**: 
  ```typescript
  // neph-client.ts
  await this.client.executeLua(RPC_CALL, [
    "review.open",
    {
      path: filePath,
      content,
      request_id: requestId,
      channel_id: this.channelId,
      result_path: `/tmp/neph-review-${requestId}.json`,  // NEW
    },
  ]);
  ```

**4. Complete protocol validation with automated checking**
- **Decision**: Update TypeScript tests to validate all methods from protocol.json
- **Rationale**: Prevents silent contract mismatches between Lua and TypeScript
- **Alternative considered**: Generate TypeScript types from protocol.json - more complex but could be future improvement
- **Implementation**: Update `contract.test.ts` expected methods list

**5. Socket discovery with heuristic scoring**
- **Decision**: Add scoring system for ambiguous socket matches in monorepos
- **Rationale**: Better user experience while maintaining conservative defaults
- **Alternative considered**: Always require NVIM_SOCKET_PATH for ambiguity - too strict
- **Implementation**: Score sockets by directory depth match, pick highest score if above threshold

## Risks / Trade-offs

**Risks:**
1. **Race condition fixes may introduce deadlocks** → Mitigation: Use simple flag-based approach, not complex locking
2. **File cleanup improvements may fail on network filesystems** → Mitigation: Add retry with exponential backoff
3. **Socket discovery heuristics could pick wrong instance** → Mitigation: Maintain conservative threshold, fall back to null
4. **Additional result_path parameter may break existing extension agents** → Mitigation: Parameter is optional in Lua, backward compatible

**Trade-offs:**
1. **Simplicity vs completeness**: Choosing simpler solutions over comprehensive ones to maintain code clarity
2. **Reliability vs performance**: Some fixes add small overhead (file writes, extra checks) for reliability
3. **User experience vs safety**: Socket discovery heuristics improve UX but have small risk of wrong match

**Migration Plan:**
No migration needed - all changes are backward compatible. Implementation can be deployed incrementally.

**Open Questions:**
1. Should we add a configuration option to disable socket discovery heuristics for users who prefer strict behavior?
2. Should result_path files have automatic cleanup (TTL) to avoid disk usage accumulation?
3. Should we add integration tests that actually spawn Neovim instances for end-to-end validation?