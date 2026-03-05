## 1. Pure Lua API Layer (Phase 1)

- [ ] 1.1 Create `lua/neph/api/init.lua` with public exports
- [ ] 1.2 Create `lua/neph/api/write.lua` with `file(path, content)` function
- [ ] 1.3 Create `lua/neph/api/edit.lua` with `file(path, old_text, new_text)` function
- [ ] 1.4 Create `lua/neph/api/delete.lua` with `file(path)` function
- [ ] 1.5 Create `lua/neph/api/read.lua` with `file(path)` function
- [ ] 1.6 Add path validation utilities in `lua/neph/api/validation.lua`
- [ ] 1.7 Add error handling utilities in `lua/neph/api/errors.lua`
- [ ] 1.8 Extract existing tool logic from `tools.lua` to new API layer
- [ ] 1.9 Update `tools.lua` to call new API internally
- [ ] 1.10 Add EmmyLua annotations to all API functions

## 2. Unit Tests for Lua API

- [ ] 2.1 Create `tests/unit/api/write_spec.lua` with plenary
- [ ] 2.2 Create `tests/unit/api/edit_spec.lua` with plenary
- [ ] 2.3 Create `tests/unit/api/delete_spec.lua` with plenary
- [ ] 2.4 Create `tests/unit/api/read_spec.lua` with plenary
- [ ] 2.5 Create `tests/unit/api/validation_spec.lua` for path validation
- [ ] 2.6 Add test helpers in `tests/helpers/filesystem.lua` for mocked fs operations
- [ ] 2.7 Verify all unit tests pass with `task test:unit`
- [ ] 2.8 Measure code coverage and ensure ≥ 70% for `lua/neph/api/`

## 3. Tool Registry Infrastructure

- [ ] 3.1 Create `lua/neph/registry/init.lua` with tool registry
- [ ] 3.2 Implement `register_tool(definition)` function
- [ ] 3.3 Implement `unregister_tool(name)` function
- [ ] 3.4 Implement `list_tools()` function
- [ ] 3.5 Implement `get_tool(name)` function
- [ ] 3.6 Add tool adapter interface definition
- [ ] 3.7 Create default adapter wrapping Lua API
- [ ] 3.8 Add unit tests for registry in `tests/unit/registry_spec.lua`

## 4. Protocol Adapter Interface

- [ ] 4.1 Create `lua/neph/protocols/init.lua` with protocol interface
- [ ] 4.2 Define protocol adapter interface (capabilities, execute, cleanup methods)
- [ ] 4.3 Create `lua/neph/protocols/shim.lua` wrapping existing subprocess logic
- [ ] 4.4 Move shim subprocess logic from existing code to shim protocol adapter
- [ ] 4.5 Add protocol selection to agent config schema in `lua/neph/config.lua`
- [ ] 4.6 Add protocol negotiation logic in `lua/neph/internal/session.lua`
- [ ] 4.7 Update agent initialization to use protocol adapters

## 5. Node Client Package (Phase 2)

- [ ] 5.1 Create `tools/client/` directory structure
- [ ] 5.2 Create `tools/client/package.json` with dependencies (@neovim/node-client, typescript)
- [ ] 5.3 Create `tools/client/src/index.ts` with NephClient class
- [ ] 5.4 Implement `writeFile(path, content)` method
- [ ] 5.5 Implement `editFile(path, oldText, newText)` method
- [ ] 5.6 Implement `deleteFile(path)` method
- [ ] 5.7 Implement `readFile(path)` method
- [ ] 5.8 Implement connection management and auto-discovery
- [ ] 5.9 Add error classes (NephNotFoundError, FileNotFoundError, PermissionError)
- [ ] 5.10 Add TypeScript type definitions
- [ ] 5.11 Build package with `npm run build`

## 6. RPC Protocol Adapter

- [ ] 6.1 Create `lua/neph/protocols/rpc.lua` protocol adapter
- [ ] 6.2 Implement RPC protocol initialization and socket verification
- [ ] 6.3 Implement tool execution via RPC (route to Lua API)
- [ ] 6.4 Add RPC protocol to protocol selection logic
- [ ] 6.5 Update agent config to support `protocol = "rpc"` option
- [ ] 6.6 Add fallback logic when RPC fails (try next protocol)

## 7. Integration Tests for Node Client + RPC

- [ ] 7.1 Create `tests/integration/` directory structure
- [ ] 7.2 Create `tests/integration/setup.ts` with headless Neovim spawning
- [ ] 7.3 Create `tests/integration/rpc-protocol.test.ts`
- [ ] 7.4 Test write file operation via RPC
- [ ] 7.5 Test edit file operation via RPC
- [ ] 7.6 Test delete file operation via RPC
- [ ] 7.7 Test read file operation via RPC
- [ ] 7.8 Test connection failure and error handling
- [ ] 7.9 Add vitest configuration in `tools/client/vitest.config.ts`
- [ ] 7.10 Verify integration tests pass with `npm test` in tools/client/

## 8. Update Pi Agent to Use Node Client

- [ ] 8.1 Update `tools/pi/package.json` to include `@neph/client` dependency
- [ ] 8.2 Refactor `tools/pi/pi.ts` to import NephClient
- [ ] 8.3 Replace shim.py subprocess calls with NephClient method calls
- [ ] 8.4 Add opt-in config flag `use_rpc_protocol` to pi agent config
- [ ] 8.5 Maintain backward compatibility with shim protocol by default
- [ ] 8.6 Test pi agent with both RPC and shim protocols

## 9. WebSocket Protocol Implementation (Phase 3)

- [ ] 9.1 Create `lua/neph/protocols/websocket.lua` protocol adapter
- [ ] 9.2 Implement TCP server using `vim.loop.new_tcp()`
- [ ] 9.3 Implement port binding and random port assignment
- [ ] 9.4 Create lockfile at `vim.fn.stdpath("data")/neph/sockets/[pid].lock`
- [ ] 9.5 Implement JSON-RPC 2.0 message parsing
- [ ] 9.6 Implement request routing to Lua API
- [ ] 9.7 Implement response serialization
- [ ] 9.8 Add connection limit enforcement (default 5 connections)
- [ ] 9.9 Add VimLeavePre autocmd for cleanup
- [ ] 9.10 Implement stale lockfile cleanup on startup

## 10. WebSocket Event Streaming

- [ ] 10.1 Create `lua/neph/api/events.lua` for event emission
- [ ] 10.2 Implement `file_changed` event on file writes/edits
- [ ] 10.3 Implement `diagnostics_updated` event via vim.diagnostic
- [ ] 10.4 Implement `selection_changed` event via visual mode tracking
- [ ] 10.5 Add event subscription mechanism to WebSocket protocol
- [ ] 10.6 Broadcast events to all connected WebSocket clients
- [ ] 10.7 Add event filtering based on client subscriptions

## 11. Script Tool Protocol Implementation

- [ ] 11.1 Create `lua/neph/protocols/script.lua` protocol adapter
- [ ] 11.2 Implement toolbox directory discovery ($NEPH_TOOLBOX or default)
- [ ] 11.3 Implement executable script scanning with permission check
- [ ] 11.4 Implement describe action invocation (`NEPH_ACTION=describe`)
- [ ] 11.5 Implement execute action invocation (`NEPH_ACTION=execute`)
- [ ] 11.6 Add JSON input/output handling for stdin/stdout
- [ ] 11.7 Add environment variable setup (NEPH_SESSION_ID, NVIM_SOCKET)
- [ ] 11.8 Implement input schema validation
- [ ] 11.9 Add timeout enforcement (30 seconds default)
- [ ] 11.10 Add tool schema caching

## 12. Lifecycle Hooks System

- [ ] 12.1 Create `lua/neph/hooks/init.lua` with hook registry
- [ ] 12.2 Implement `register_hook(event, handler)` function
- [ ] 12.3 Implement `execute_hooks(event, context)` function
- [ ] 12.4 Add hook discovery from `~/.neph/hooks/` directory
- [ ] 12.5 Implement session_start hook event
- [ ] 12.6 Implement session_end hook event (async, 5s timeout)
- [ ] 12.7 Implement pre_tool hook event (with cancellation support)
- [ ] 12.8 Implement post_tool hook event
- [ ] 12.9 Implement post_tool_failure hook event
- [ ] 12.10 Add hook configuration to agent config schema

## 13. Integration Tests for WebSocket + Script Protocols

- [ ] 13.1 Create `tests/integration/websocket-protocol.test.ts`
- [ ] 13.2 Test WebSocket server startup and lockfile creation
- [ ] 13.3 Test JSON-RPC request/response cycle
- [ ] 13.4 Test event streaming to WebSocket clients
- [ ] 13.5 Test connection limit enforcement
- [ ] 13.6 Create `tests/integration/script-protocol.test.ts`
- [ ] 13.7 Create temporary test scripts for integration tests
- [ ] 13.8 Test script describe action
- [ ] 13.9 Test script execute action with JSON input
- [ ] 13.10 Test script timeout and error handling

## 14. Protocol Negotiation and Configuration

- [ ] 14.1 Add `protocols` field to agent config (array of protocol names in priority order)
- [ ] 14.2 Implement protocol capability checking (events, bidirectional, etc.)
- [ ] 14.3 Implement protocol fallback logic when first choice fails
- [ ] 14.4 Add protocol validation at config time
- [ ] 14.5 Add deprecation warnings for shim protocol
- [ ] 14.6 Document protocol selection in README
- [ ] 14.7 Create protocol comparison table in documentation

## 15. Testing Infrastructure

- [ ] 15.1 Reorganize tests into `tests/unit/`, `tests/integration/`, `tests/e2e/`
- [ ] 15.2 Create mock Neovim instance in `tests/helpers/mock_nvim.lua`
- [ ] 15.3 Create mock filesystem in `tests/helpers/mock_fs.lua`
- [ ] 15.4 Create mock protocol adapters in `tests/helpers/mock_protocol.lua`
- [ ] 15.5 Add `task test:unit` to Taskfile.yml
- [ ] 15.6 Add `task test:integration` to Taskfile.yml
- [ ] 15.7 Add `task test:e2e` to Taskfile.yml
- [ ] 15.8 Add `task test:coverage` with coverage reporting
- [ ] 15.9 Update CI pipeline to run all test layers
- [ ] 15.10 Configure parallel test execution in CI

## 16. End-to-End Tests

- [ ] 16.1 Create `tests/e2e/` directory structure
- [ ] 16.2 Create `tests/e2e/pi-agent.sh` for pi agent workflow
- [ ] 16.3 Create `tests/e2e/multi-protocol.sh` for concurrent protocol test
- [ ] 16.4 Add timeout enforcement (60 seconds per e2e test)
- [ ] 16.5 Add cleanup logic to e2e tests (remove temp files)
- [ ] 16.6 Verify e2e tests complete in < 5 minutes total

## 17. Documentation and Migration Guide

- [ ] 17.1 Update README.md with protocol architecture overview
- [ ] 17.2 Create protocol comparison table (WebSocket, RPC, Script, Shim)
- [ ] 17.3 Document protocol selection in agent configuration
- [ ] 17.4 Create migration guide for custom agents
- [ ] 17.5 Create `docs/protocols/websocket.md` documentation
- [ ] 17.6 Create `docs/protocols/rpc.md` documentation
- [ ] 17.7 Create `docs/protocols/script.md` documentation
- [ ] 17.8 Create `docs/migration.md` with migration timeline
- [ ] 17.9 Add examples for each protocol in `examples/` directory
- [ ] 17.10 Update CHANGELOG.md with breaking changes and migration notes

## 18. Final Integration and Release

- [ ] 18.1 Run full test suite (unit + integration + e2e)
- [ ] 18.2 Verify code coverage meets thresholds (70% unit, 25% integration)
- [ ] 18.3 Run all linters (stylua, luacheck, deno lint, flake8)
- [ ] 18.4 Test with all built-in agents (pi, goose, claude, etc.)
- [ ] 18.5 Test protocol fallback scenarios
- [ ] 18.6 Test backward compatibility with existing configs
- [ ] 18.7 Update version number in appropriate files
- [ ] 18.8 Tag release as `v1.0.0-api-layer` (Phase 1 complete)
- [ ] 18.9 After RPC completion, tag as `v1.1.0-rpc-protocol`
- [ ] 18.10 After WebSocket+Script completion, tag as `v2.0.0-multi-protocol`
