## 1. Simplify neph-cli review (one protocol, no agent awareness)

- [x] 1.1 Delete `tools/neph-cli/src/normalizers/` directory (types.ts, claude.ts, gemini.ts, signal.ts, index.ts)
- [x] 1.2 Delete `tools/neph-cli/tests/normalizers.test.ts`
- [x] 1.3 Rewrite `tools/neph-cli/src/review.ts` — remove `agent` param, remove normalizer lookup, remove per-agent formatters. Reads `{ path, content }` from stdin, returns `{ decision, content, reason? }` on stdout. Fail-open when Neovim unreachable.
- [x] 1.4 Update `tools/neph-cli/src/index.ts` — remove `--agent` branch from review command, remove gate import, simplify review routing to call `runReview({ stdin, timeout, transport })`
- [x] 1.5 Rewrite `tools/neph-cli/tests/review.test.ts` — test only neph protocol (`{ path, content }` in, `{ decision, content }` out), test fail-open on no socket, test timeout exit code 3, test no-changes auto-accept, test dry-run
- [x] 1.6 Update `.cupcake/rulebook.yml` — change signal command from `neph-cli review --agent signal` to `neph-cli review`

## 2. Update specs to match new design

- [x] 2.1 Rewrite `specs/neph-cli/spec.md` — remove all `--agent` references, remove per-agent formatters, remove normalizer mentions. Align with `specs/neph-review-command/spec.md` (one protocol only).
- [x] 2.2 Update `specs/cupcake-integration/spec.md` — add outside-Neovim scenario (fail-open, deterministic policies still enforce)
- [x] 2.3 Update `specs/testing-infrastructure/spec.md` — remove normalizer test references, add neph protocol tests

## 3. Cupcake Policy Suite (done except reconstruction)

- [x] 3.1 Create `.cupcake/policies/neph/review.rego`
- [x] 3.2 Create `.cupcake/policies/neph/dangerous_commands.rego`
- [x] 3.3 Create `.cupcake/policies/neph/protected_paths.rego`
- [x] 3.4 Add routing metadata to all policies
- [x] 3.5 Create `.cupcake/rulebook.yml`
- [x] 3.6 Write OPA test files for all policies (19/19 passing)
- [x] 3.7 Add edit reconstruction signal — `neph_reconstruct` script that reads the file and applies old_str/new_str, producing `{ path, content }` for the review signal
- [x] 3.8 Update review.rego to handle reconstruct signal output for edit tools

## 4. Review Protocol Changes (Lua side — done)

- [x] 4.1 Modify `lua/neph/api/review/init.lua` — review.open returns envelope via notification
- [x] 4.2 Remove `result_path` and `channel_id` from required params
- [x] 4.3 Remove `review.pending` handler
- [x] 4.4 Update `protocol.json` — remove bus.register, review.pending
- [x] 4.5 Update `lua/neph/rpc.lua` — remove bus.register and review.pending routes

## 5. Cupcake Pi Harness

- [x] 5.1 Finalize `tools/pi/cupcake-harness.ts` — verify event format matches Cupcake expectations, ensure no fallback path
- [x] 5.2 Verify `assertCupcakeInstalled()` throws at session_start
- [x] 5.3 Edit reconstruction in harness — read file, apply old_text/new_text before passing to Cupcake
- [x] 5.4 Session lifecycle events via neph-cli (set/unset status)
- [x] 5.5 Pass through non-mutation tools without Cupcake
- [x] 5.6 Write vitest tests — mock `execFileSync` for Cupcake eval, test allow/deny/modify, test missing Cupcake throws, test lifecycle

## 6. Hook Configuration (all hooks → Cupcake)

- [x] 6.1 Generate `.claude/settings.json` hook config — PreToolUse for Write|Edit → `cupcake eval --harness claude`
- [x] 6.2 Generate `.gemini/settings.json` hook config — BeforeTool for write_file|edit_file|replace → `cupcake eval --harness gemini`
- [x] 6.3 Cupcake initialization in `tools.lua` — deploy policies, configure rulebook, require Cupcake on PATH
- [x] 6.4 Update `lua/neph/agents/claude.lua` — remove old gate-based launch_args_fn, point to Cupcake hook config
- [x] 6.5 Update `lua/neph/agents/gemini.lua` — remove MCP companion sidecar config, point to Cupcake hook config
- [x] 6.6 Update `lua/neph/agents/pi.lua` — change type, update tools manifest for Cupcake harness

## 7. Dead Code Removal

- [x] 7.1 Delete `tools/neph-cli/src/gate.ts`
- [x] 7.2 Delete `tools/neph-cli/tests/gate.test.ts`, `gate.fuzz.test.ts`, `gate.contract.test.ts`
- [x] 7.3 Delete `tools/lib/neph-client.ts` (NephClient SDK)
- [x] 7.4 Delete `tools/lib/tests/neph-client.test.ts`
- [x] 7.5 Delete `lua/neph/internal/bus.lua`
- [x] 7.6 Delete `tests/bus_spec.lua`
- [x] 7.7 Delete `tools/gemini/src/companion.ts`, `diff_bridge.ts`, `discovery.ts`, `server.ts`
- [x] 7.8 Remove bus references from `lua/neph/init.lua` and `session.lua`
- [x] 7.9 Remove extension agent type handling from `session.lua` (bus routing, companion sidecar)
- [ ] 7.10 Remove `neph-client.ts` imports from amp, opencode tool files (deferred — needs separate Cupcake harness rewrites)
- [x] 7.11 Remove gate import from `tools/neph-cli/src/index.ts`

## 8. End-to-End Tests

- [x] 8.1 Write neph-cli protocol integration test — subprocess + dry-run/fail-open + verify `{ decision, content }` output shape (4 tests passing)
- [ ] 8.2 Write Claude E2E test — full `cupcake eval --harness claude` (requires live Cupcake, deferred to post-install verification)
- [ ] 8.3 Write Gemini E2E test — full `cupcake eval --harness gemini` (requires live Cupcake, deferred)
- [ ] 8.4 Write Pi E2E test — Pi harness → cupcake eval (requires live Cupcake, deferred)
- [ ] 8.5 Write timeout E2E test — verify exit code 3 propagates through Cupcake (requires live Cupcake, deferred)
- [x] 8.6 Update contract tests (`tests/rpc_spec.lua`) — verify bus.register and review.pending return METHOD_NOT_FOUND

## 9. Taskfile & CI Updates

- [x] 9.1 Add `test:rego` task to Taskfile.yml
- [x] 9.2 Add `test:e2e:review` task
- [x] 9.3 Update `test` task to include rego subtask
- [ ] 9.4 Update `.fluentci/ci.ts` — add OPA + Cupcake to Nix deps (deferred — CI pipeline change)
- [x] 9.5 Update `build` task and tools/Taskfile.yml — Pi harness build, remove test:lib
