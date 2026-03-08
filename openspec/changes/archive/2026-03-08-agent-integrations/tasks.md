## 1. Shared neph-run Library

- [x] 1.1 Create `tools/lib/neph-run.ts` — extract `nephRun()`, `review()`, and fire-and-forget `neph()` from pi.ts into shared module with proper TypeScript types (ReviewEnvelope, NEPH_TIMEOUT_MS)
- [x] 1.2 Create `tools/lib/package.json` with devDependencies for testing
- [x] 1.3 Write vitest tests for `lib/neph-run.ts` — mock child_process spawn, test nephRun success/failure/timeout, review envelope parsing, neph serial queue ordering
- [x] 1.4 Refactor `tools/pi/pi.ts` to import `nephRun`, `review`, `neph` from `../lib/neph-run` — remove inline definitions, verify all pi tests still pass

## 2. Gate Subcommand

- [x] 2.1 Add `gate` command to `tools/neph-cli/src/index.ts` — read stdin JSON, accept `--agent <name>` flag, normalize to `{ filePath, content }`
- [x] 2.2 Implement agent format normalizers: claude (tool_input.file_path + content or old_str/new_str), copilot (JSON.parse toolArgs string, extract filepath + content), gemini (tool_input.filepath [no underscore] + content), cursor (post-write only: file_path + edits array — no review, just checktime + state)
- [x] 2.3 Gate calls review flow internally (reuse existing runCommand logic), manages vim.g state (status.set/unset around review)
- [x] 2.4 Handle edge cases: no socket (exit 0), dry-run (exit 0), unknown agent (exit 0 + warning), review timeout (exit 2)
- [x] 2.5 Write vitest tests for gate command — FakeTransport, test each agent normalizer, test accept/reject exit codes, test edge cases

## 3. Agent Capability Metadata

- [x] 3.1 Add `integration` field to agent definitions in `lua/neph/internal/agents.lua` — type ("hook"/"extension"/nil) + capabilities list for each agent
- [x] 3.2 Update `session.lua` open/kill to check `integration.type` — set vim.g state only for nil (terminal-only) agents
- [x] 3.3 Update `session.lua` VimLeavePre cleanup to clear state only for tracked terminal-only agents
- [x] 3.4 Write plenary/busted tests for capability-driven state management — terminal-only gets state, hook/extension agents don't, backward compat for agents without integration field

## 4. Claude Code Hook Config

- [x] 4.1 Create `tools/claude/settings.json` — PreToolUse hook with matcher `"Edit|Write"`, command `"neph gate --agent claude"`
- [x] 4.2 Write vitest test validating settings.json structure (parses, has hooks.PreToolUse, correct matcher and command)

## 5. Copilot Hook Config

- [x] 5.1 Create `tools/copilot/hooks.json` — preToolUse hook for edit/create, command `"neph gate --agent copilot"`
- [x] 5.2 Write vitest test validating hooks.json structure

## 6. Cursor Hook Config

- [x] 6.1 Create `tools/cursor/hooks.json` — afterFileEdit hook (informational only, cannot block), command `"neph gate --agent cursor"` — triggers checktime + statusline state, NOT review gating
- [x] 6.2 Write vitest test validating hooks.json structure

## 7. Gemini Hook Config

- [x] 7.1 Create `tools/gemini/settings.json` — BeforeTool hook, command `"neph gate --agent gemini"`
- [x] 7.2 Write vitest test validating settings.json structure

## 8. Amp Plugin Adapter

- [x] 8.1 Create `tools/amp/neph-plugin.ts` — Amp plugin with `@i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now` comment, `tool.call` handler intercepting file write tools, returns `{ action: 'allow' }` or `{ action: 'reject-and-continue', message }`, using `review()` from lib/neph-run
- [x] 8.2 Write vitest tests — mock nephRun, test allow/reject-and-continue flows, statusline state management (no package.json needed — Bun-based)

## 9. OpenCode Custom Tool Adapters

- [x] 9.1 Create `tools/opencode/write.ts` — overrides built-in `write` tool using `tool()` helper from `@opencode-ai/plugin`, routes through `review()` from lib/neph-run, manages vim.g state
- [x] 9.2 Create `tools/opencode/edit.ts` — overrides built-in `edit` tool, reads current file, applies edit, routes full content through `review()`, manages vim.g state
- [x] 9.3 Write vitest tests — mock nephRun, test accept/reject flows (no package.json needed — standalone files)

## 10. tools.lua Install Updates

- [x] 10.1 Add JSON merge helper to `tools.lua` — reads existing settings file, merges `hooks` key, writes back. Falls back to full write if no existing file.
- [x] 10.2 Add install entries for hook configs: claude (merge), gemini (merge), copilot (symlink), cursor (symlink)
- [x] 10.3 Add install entries for TS adapters: amp (symlink neph-plugin.ts to ~/.config/amp/plugins/), opencode (symlink write.ts + edit.ts to ~/.config/opencode/tools/)
- [x] 10.4 Verify existing pi and neph-cli install entries are unchanged

## 11. Taskfile & CI

- [x] 11.1 Update `tools/Taskfile.yml` — add test tasks for lib, amp, opencode; add lint tasks for new TS files
- [x] 11.2 Update `.fluentci/ci.ts` — add `npm ci` for tools/lib (amp and opencode are standalone files, no npm ci needed)
- [x] 11.3 Verify `task ci` passes locally with all new tests
- [x] 11.4 Verify `task dagger` passes locally
- [x] 11.5 Update `tools/README.md` to document all agent integrations and the neph gate command

## 12. Pi Regression & Final Verification

- [x] 12.1 Run `task tools:test:pi` — all existing tests pass after refactor to shared lib
- [x] 12.2 Run full `task test` — no regressions across Lua and TS tests
- [x] 12.3 Run full `task ci` — lint + test all pass
- [x] 12.4 Verify pi symlinks still point to correct sources
