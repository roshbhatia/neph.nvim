## 1. Shared infrastructure: `tools/lib/harness-base.ts`

- [x] 1.1 Create `tools/lib/harness-base.ts` with `ContentHelper` — `reconstructContent(filePath, toolInput)` that handles `content` field, `old_string`+`new_string` replacement, reads current file, falls back gracefully on missing file or non-matching old_string
- [x] 1.2 Add `CupcakeHelper` to `harness-base.ts` — `cupcakeEval(harnessName, event)` synchronous via `execFileSync`, returns `CupcakeDecision` (`allow|deny|block|ask|modify`), returns `deny` on Cupcake not found, 600s timeout
- [x] 1.3 Add `SessionHelper` to `harness-base.ts` — `createSessionSignals(agentName)` returning `{ setActive, unsetActive, setRunning, unsetRunning, checktime, close }` backed by `createPersistentQueue` from `neph-run.ts`
- [x] 1.4 Export shared types: `CupcakeDecision`, `HookDecision`, `WriteEvent` from `harness-base.ts`
- [x] 1.5 Add unit tests for `ContentHelper.reconstructContent` covering: content field, old+new replacement, new file (missing), old_string mismatch fallback

## 2. Amp — add Cupcake policy layer + partial accept

- [x] 2.1 Import `CupcakeHelper` and `ContentHelper` from `tools/lib/harness-base.ts` in `neph-plugin.ts`
- [x] 2.2 In the `tool.call` handler, replace the direct `review()` call with `cupcakeEval("amp", normalizedEvent)` — route through Cupcake for policy enforcement (protected_paths, dangerous_commands) before neph review
- [x] 2.3 Add `{ action: 'modify', input: {...} }` return path: when Cupcake returns a `modify` decision with `updated_input.content`, reconstruct the modified tool input and return `{ action: 'modify', input: modifiedInput }` to Amp
- [x] 2.4 Update `neph-plugin.ts` to use `ContentHelper.reconstructContent` instead of the inline content reconstruction logic
- [x] 2.5 Verify `amp` harness name works with `cupcake eval --harness amp` (check `.cupcake/` policies cover amp or create harness entry)

## 3. Gemini — add Cupcake policy layer + lifecycle hooks

- [x] 3.1 Refactor `runGeminiHook` in `integration.ts` to use `CupcakeHelper.cupcakeEval("gemini", ...)` before calling `runReview` directly — Cupcake policy layer must run first
- [x] 3.2 Add `ContentHelper.reconstructContent` to replace inline `reconstructGeminiContent` logic (or delegate to it)
- [x] 3.3 Add lifecycle hook dispatch in `runGeminiHook`: `SessionStart` → `signals.setActive()`, `SessionEnd` → `signals.unsetActive() + signals.close()`, `BeforeAgent` → `signals.setRunning()`, `AfterAgent` → `signals.unsetRunning() + signals.checktime()`
- [x] 3.4 Update `tools/gemini/settings.json` to add `SessionStart`, `SessionEnd`, `BeforeAgent`, `AfterAgent` hook entries pointing to `neph integration hook gemini`
- [x] 3.5 Thread `updated_input` from Cupcake `modify` decision back as `hookSpecificOutput.tool_input` content for write_file (Gemini partial accept)

## 4. Claude — structured hook handler (replaces exit-code shell command)

- [x] 4.1 Add `runClaudeHook(stdin, transport)` handler in `integration.ts` — parses `hook_event_name` from stdin JSON, dispatches to lifecycle or tool evaluation
- [x] 4.2 Lifecycle dispatch: `SessionStart` → `signals.setActive()`, `SessionEnd` → `signals.unsetActive()`, `UserPromptSubmit` → `signals.setRunning()`, `Stop` → `signals.unsetRunning() + signals.checktime()`
- [x] 4.3 `PreToolUse` (matcher: `Edit|Write|MultiEdit`) dispatch: use `CupcakeHelper.cupcakeEval("claude", event)`, map decision to `hookSpecificOutput` with `permissionDecision: "allow"|"deny"` and `updatedInput` for `modify` decisions
- [x] 4.4 `PostToolUse` (matcher: `Edit|Write|MultiEdit`) dispatch: `signals.checktime()`
- [x] 4.5 All hook responses: write JSON to stdout and exit 0 (no exit-code hacks); pass-through unknown hook names with `{}`
- [x] 4.6 Wire `hook` subcommand dispatch in `runIntegrationCommand`: `neph integration hook claude` → `runClaudeHook`
- [x] 4.7 Update `tools/claude/settings.json`: replace `"command": "cupcake eval --harness claude"` with `"command": "neph integration hook claude"` for PreToolUse; add PostToolUse, SessionStart, SessionEnd, UserPromptSubmit, Stop hook entries

## 5. Codex — new TypeScript hook handler

- [x] 5.1 Add `runCodexHook(stdin, transport)` in `integration.ts` — same structure as Claude handler (PreToolUse, PostToolUse, lifecycle events)
- [x] 5.2 Wire `neph integration hook codex` dispatch in `runIntegrationCommand`
- [x] 5.3 Create `tools/codex/` directory with `hooks.json` template — PreToolUse (edit|write|create), PostToolUse, UserPromptSubmit/Stop lifecycle hooks all pointing to `neph integration hook codex`
- [x] 5.4 Add codex to `INTEGRATIONS` array in `integration.ts` with `kind: "hooks"`, `requiresCupcake: true`, config path `~/.codex/hooks.json` (global) or `.codex/hooks.json` (project)
- [x] 5.5 Update `tools/neph-cli/package.json` or build config if needed for new codex template

## 6. Copilot — structured hook handler + lifecycle

- [x] 6.1 Add `runCopilotHook(stdin, transport)` in `integration.ts` — dispatches `preToolUse`, `postToolUse`, `sessionStart`, `sessionEnd`
- [x] 6.2 `preToolUse` path: `cupcakeEval("copilot", event)` → return `{ permissionDecision: "allow"|"deny" }` (no `updatedInput` — Copilot API limitation)
- [x] 6.3 `postToolUse` path: `signals.checktime()`
- [x] 6.4 `sessionStart`/`sessionEnd`: lifecycle signals
- [x] 6.5 Wire `neph integration hook copilot` dispatch
- [x] 6.6 Update `tools/copilot/hooks.json` template: replace `cupcake eval --harness copilot` with `neph integration hook copilot`; add `postToolUse`, `sessionStart`, `sessionEnd` entries

## 7. Cursor — correct integration

- [x] 7.1 Add `runCursorHook(stdin, transport)` in `integration.ts` — dispatches `afterFileEdit` (checktime only), `beforeShellExecution` (Cupcake eval), `beforeMCPExecution` (Cupcake eval)
- [x] 7.2 `afterFileEdit`: call `signals.checktime()` only — no review attempt (file already written; permanent Cursor limitation)
- [x] 7.3 `beforeShellExecution`: `cupcakeEval("cursor", event)` — gate shell commands through Cupcake policy; return `{ permission: "allow"|"deny" }` in Cursor's hook output format
- [x] 7.4 `beforeMCPExecution`: same as `beforeShellExecution` but for MCP tool calls
- [x] 7.5 Wire `neph integration hook cursor` dispatch
- [x] 7.6 Update `tools/cursor/hooks.json` template: replace current `afterFileEdit` cupcake command with `neph integration hook cursor`; add `beforeShellExecution` and `beforeMCPExecution` entries

## 8. OpenCode — session lifecycle signals

- [x] 8.1 In `lua/neph/internal/session.lua` `open()`: after setting `vim.g[termname.."_active"] = true` for opencode, also call `neph-cli set opencode_active true` via the existing channel (or via `pcall(require("neph.internal.channel").rpc_notify, ...)`)
- [x] 8.2 In `kill_session`: for opencode, call `neph-cli unset opencode_active` (matching `vim.g` clear that already happens)
- [x] 8.3 Wire `opencode_running` state: in opencode_permission.lua, set `opencode_running` when a permission.asked event arrives (agent is working) and unset on `file.edited` (agent finished writing)
- [x] 8.4 Verify statusline/winbar reads `opencode_active` and `opencode_running` correctly (same key pattern as other agents)

## 9. Tests and validation

- [x] 9.1 Add tests for `CupcakeHelper.cupcakeEval` — mock execFileSync, verify: allow passthrough, deny passthrough, modify with updated_input, error handling when cupcake not found
- [x] 9.2 Add tests for `runClaudeHook` — mock cupcakeEval and signals; verify: SessionStart sets active, PreToolUse with deny returns hookSpecificOutput deny, PreToolUse with modify returns updatedInput, PostToolUse calls checktime
- [x] 9.3 Add tests for `runGeminiHook` (upgraded) — verify Cupcake is called before review, lifecycle signals fire for BeforeAgent/AfterAgent
- [x] 9.4 Add tests for `runCursorHook` — verify afterFileEdit fires checktime only (no review), beforeShellExecution routes to Cupcake
- [x] 9.5 Run full neph-cli test suite; ensure zero regressions
- [x] 9.6 Run full Lua test suite; ensure zero regressions
