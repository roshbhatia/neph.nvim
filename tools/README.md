# neph.nvim tools

Companion tooling bundled with neph.nvim. `require("neph").setup()` automatically
installs the relevant files to their expected locations.

## Architecture

All agent hooks point to **Cupcake** (`cupcake eval`). Cupcake evaluates policies
and invokes `neph-cli` as a signal for interactive review. No agent ever calls
`neph-cli` directly.

```
tools/
  neph-cli/          CLI binary (neph) — review, set/unset, checktime, ui-*
  pi/                Pi Cupcake harness (intercepts tool_call → cupcake eval)
  lib/               Shared utilities — neph-run.ts (CLI wrapper), log.ts
  amp/               Amp plugin (pending Cupcake harness support)
  opencode/          OpenCode (uses native Cupcake plugin)
  claude/            Claude Code hook config
  copilot/           Copilot hook config
  cursor/            Cursor hook config
  gemini/            Gemini hook config
```

## Agent Integration

| Agent | Mechanism | Review |
|-------|-----------|--------|
| Claude | `PreToolUse` hook → `cupcake eval --harness claude` | YES |
| Gemini | `BeforeTool` hook → `cupcake eval --harness gemini` | YES |
| Pi | Extension → `cupcake eval --harness pi` | YES |
| OpenCode | Native Cupcake plugin | YES |
| Amp | Terminal-only (Cupcake harness pending) | NO |
| Goose, Codex, Crush | Terminal-only | NO |

## `neph-cli review`

Editor abstraction for interactive code review. Called by Cupcake's
`neph_review` signal, not by agents directly.

**Protocol:**
- stdin: `{ "path": "/abs/path", "content": "proposed content" }`
- stdout: `{ "decision": "accept|reject|partial", "content": "...", "reason?": "..." }`
- Exit codes: `0` = accept/partial, `2` = reject, `3` = timeout

```sh
# Called by Cupcake signal, not by users directly
echo '{"path":"/tmp/f.lua","content":"hello"}' | neph-cli review
```

## Cupcake Policies

Rego policies in `.cupcake/policies/neph/`:
- `review.rego` — routes write/edit tools through interactive review
- `dangerous_commands.rego` — blocks rm -rf, force push, --no-verify
- `protected_paths.rego` — blocks writes to .env, credentials, SSH keys

Signals in `.cupcake/signals/`:
- `neph_review` — chains reconstruct + review
- `neph_reconstruct` — normalizes agent JSON to `{ path, content }`

## Install Targets

| Source | Destination | Method |
|--------|------------|--------|
| `neph-cli/dist/index.js` | `~/.local/bin/neph` | symlink (opt-in) |
| `pi/dist/cupcake-harness.js` | `~/.pi/agent/extensions/nvim/dist` | symlink |
| `.cupcake/policies/` | `.cupcake/policies/neph/` | file copy |
| `.cupcake/signals/` | `.cupcake/signals/` | file copy |

## Running tests

```sh
# All tool tests
task tools:test

# Individual suites
cd tools/neph-cli && npm test -- --run   # CLI + review + integration tests
cd tools/pi && npx vitest --run          # Pi Cupcake harness tests

# Rego policy tests
task test:rego                            # Requires OPA installed

# Integration tests
task test:e2e:review                      # neph-cli protocol + reconstruct signal
```
