# neph.nvim tools

Companion tooling bundled with neph.nvim. `require("neph").setup()` automatically
installs the relevant files to their expected locations.

## Architecture

```
tools/
  neph-cli/          CLI binary (neph) — review, set/unset, checktime, gate
  lib/               Shared TypeScript module — nephRun(), review(), createNephQueue()
  pi/                Pi coding agent extension (overrides write/edit tools)
  amp/               Amp plugin (tool.call handler, file write interception)
  opencode/          OpenCode custom tools (write.ts, edit.ts overrides)
  claude/            Claude Code hook config (PreToolUse)
  copilot/           Copilot hook config (preToolUse)
  cursor/            Cursor hook config (afterFileEdit — informational only)
  gemini/            Gemini hook config (BeforeTool)
```

## Agent Integration Tiers

| Tier | Agents | Mechanism | Review Gating |
|------|--------|-----------|---------------|
| Hook | Claude, Copilot, Gemini | Shell hook → `neph gate` | YES |
| Hook (post-write) | Cursor | `afterFileEdit` hook | NO (informational) |
| Extension | Pi, Amp, OpenCode | TS plugin overrides tools | YES |
| Terminal-only | Goose, Codex, Crush | No hook system | None |

## `neph gate` command

Universal hook handler for shell-hook agents. Reads agent-specific JSON from
stdin, normalizes to `{ filePath, content }`, runs the review flow.

```sh
# Called by agent hooks, not directly by users
echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/f","content":"hi"}}' | neph gate --agent claude
```

Exit codes: `0` = accept, `2` = reject.

## `lib/neph-run.ts`

Shared module used by pi, amp, and opencode adapters:
- `nephRun(args, stdin?, timeoutMs?)` — spawn neph CLI, return stdout
- `review(filePath, content)` — blocking vimdiff review, returns `ReviewEnvelope`
- `createNephQueue()` — fire-and-forget serial command queue

## Install Targets

| Source | Destination | Method |
|--------|------------|--------|
| `neph-cli/dist/index.js` | `~/.local/bin/neph` | symlink |
| `pi/package.json` | `~/.pi/agent/extensions/nvim/package.json` | symlink |
| `pi/dist` | `~/.pi/agent/extensions/nvim/dist` | symlink |
| `claude/settings.json` | `~/.claude/settings.json` | JSON merge (hooks key) |
| `gemini/settings.json` | `~/.gemini/settings.json` | JSON merge (hooks key) |
| `cursor/hooks.json` | `~/.cursor/hooks.json` | symlink |
| `amp/neph-plugin.ts` | `~/.config/amp/plugins/neph-plugin.ts` | symlink |
| `opencode/write.ts` | `~/.config/opencode/tools/write.ts` | symlink |
| `opencode/edit.ts` | `~/.config/opencode/tools/edit.ts` | symlink |
| `copilot/hooks.json` | (manual) `.github/hooks/hooks.json` | documented |

Copilot requires the hooks file committed to the project's default branch.

## Running tests

```sh
# All tool tests
task tools:test

# Individual suites
cd tools/neph-cli && npm test -- --run   # CLI + gate + hook config tests
cd tools/lib && npx vitest --run          # Shared lib tests
```
