## 1. Shared neph-run Library

- [ ] 1.1 Create `tools/lib/neph-run.ts` — extract `nephRun()`, `review()`, and fire-and-forget `neph()` from pi.ts into shared module with proper TypeScript types (ReviewEnvelope, NEPH_TIMEOUT_MS)
- [ ] 1.2 Create `tools/lib/package.json` with devDependencies for testing
- [ ] 1.3 Write vitest tests for `lib/neph-run.ts` — mock child_process spawn, test nephRun success/failure/timeout, review envelope parsing, neph serial queue ordering
- [ ] 1.4 Refactor `tools/pi/pi.ts` to import `nephRun`, `review`, `neph` from `../lib/neph-run` — remove inline definitions, verify all pi tests still pass

## 2. Gate Subcommand

- [ ] 2.1 Add `gate` command to `tools/neph-cli/src/index.ts` — read stdin JSON, accept `--agent <name>` flag, normalize to `{ filePath, content }`
- [ ] 2.2 Implement agent format normalizers: claude (tool_input.file_path + content/old_string+new_string), copilot, cursor (file_path + old_content/new_content), gemini
- [ ] 2.3 Gate calls review flow internally (reuse existing runCommand logic), manages vim.g state (status.set/unset around review)
- [ ] 2.4 Handle edge cases: no socket (exit 0), dry-run (exit 0), unknown agent (exit 0 + warning), review timeout (exit 2)
- [ ] 2.5 Write vitest tests for gate command — FakeTransport, test each agent normalizer, test accept/reject exit codes, test edge cases

## 3. Agent Capability Metadata

- [ ] 3.1 Add `integration` field to agent definitions in `lua/neph/internal/agents.lua` — type ("hook"/"extension"/nil) + capabilities list for each agent
- [ ] 3.2 Update `session.lua` open/kill to check `integration.type` — set vim.g state only for nil (terminal-only) agents
- [ ] 3.3 Update `session.lua` VimLeavePre cleanup to clear state only for tracked terminal-only agents
- [ ] 3.4 Write plenary/busted tests for capability-driven state management — terminal-only gets state, hook/extension agents don't, backward compat for agents without integration field

## 4. Claude Code Hook Config

- [ ] 4.1 Create `tools/claude/settings.json` — PreToolUse hook with matcher `"Edit|Write"`, command `"neph gate --agent claude"`
- [ ] 4.2 Write vitest test validating settings.json structure (parses, has hooks.PreToolUse, correct matcher and command)

## 5. Copilot Hook Config

- [ ] 5.1 Create `tools/copilot/hooks.json` — preToolUse hook for edit/create, command `"neph gate --agent copilot"`
- [ ] 5.2 Write vitest test validating hooks.json structure

## 6. Cursor Hook Config

- [ ] 6.1 Create `tools/cursor/hooks.json` — hook for file edits, command `"neph gate --agent cursor"`
- [ ] 6.2 Write vitest test validating hooks.json structure

## 7. Gemini Hook Config

- [ ] 7.1 Create `tools/gemini/settings.json` — BeforeTool hook, command `"neph gate --agent gemini"`
- [ ] 7.2 Write vitest test validating settings.json structure

## 8. Amp Plugin Adapter

- [ ] 8.1 Create `tools/amp/neph-plugin.ts` — plugin with tool.call event handler intercepting edit_file/create_file, using `review()` from lib/neph-run, managing vim.g state
- [ ] 8.2 Create `tools/amp/package.json` with dependencies
- [ ] 8.3 Write vitest tests — mock nephRun, test accept/reject/partial flows, state management

## 9. OpenCode Custom Tool Adapter

- [ ] 9.1 Create `tools/opencode/neph-write.ts` — custom tool overriding write/edit, using `review()` from lib/neph-run, managing vim.g state
- [ ] 9.2 Create `tools/opencode/package.json` with dependencies
- [ ] 9.3 Write vitest tests — mock nephRun, test accept/reject flows, state management

## 10. tools.lua Install Updates

- [ ] 10.1 Add JSON merge helper to `tools.lua` — reads existing settings file, merges `hooks` key, writes back. Falls back to full write if no existing file.
- [ ] 10.2 Add install entries for hook configs: claude (merge), gemini (merge), copilot (symlink), cursor (symlink)
- [ ] 10.3 Add install entries for TS adapters: amp (symlink to ~/.config/amp/plugins/neph/), opencode (symlink)
- [ ] 10.4 Verify existing pi and neph-cli install entries are unchanged

## 11. Taskfile & CI

- [ ] 11.1 Update `tools/Taskfile.yml` — add test tasks for lib, amp, opencode; add lint tasks for new TS files
- [ ] 11.2 Update `.fluentci/ci.ts` — add `npm ci` for tools/lib, tools/amp, tools/opencode
- [ ] 11.3 Verify `task ci` passes locally with all new tests
- [ ] 11.4 Verify `task dagger` passes locally
- [ ] 11.5 Update `tools/README.md` to document all agent integrations and the neph gate command

## 12. Pi Regression & Final Verification

- [ ] 12.1 Run `task tools:test:pi` — all existing tests pass after refactor to shared lib
- [ ] 12.2 Run full `task test` — no regressions across Lua and TS tests
- [ ] 12.3 Run full `task ci` — lint + test all pass
- [ ] 12.4 Verify pi symlinks still point to correct sources
