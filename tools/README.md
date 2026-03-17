# neph.nvim tools

Companion tooling bundled with neph.nvim. Integrations are installed and validated
via the `neph` CLI (`neph integration`, `neph deps`). Neovim does not install
these files automatically.

## Architecture

Integrations flow through a composable pipeline:

```
Agent event → Adapter → Policy engine → Review provider → Response formatter
```

- Policy engine: `cupcake` or `noop`
- Review provider: `vimdiff` (Neovim, opt-in) or `noop`
- Response formatter: agent-specific output schema

Hook-based agents call `neph integration hook <agent>` or Cupcake harnesses,
which invoke `neph review` when review is enabled.

```
tools/
  neph-cli/          CLI binary (neph) — integration/deps/review/status/ui-*
  pi/                Pi extension (legacy Cupcake harness)
  lib/               Shared utilities — neph-client.ts, log.ts
  amp/               Amp plugin (pending hook integration)
  opencode/          OpenCode (uses native Cupcake plugin)
  claude/            Claude Code hook config
  copilot/           Copilot hook config
  cursor/            Cursor hook config
  gemini/            Gemini hook config
```

## CLI commands

```
neph integration toggle [name]
neph integration status [name] [--show-config]
neph deps status
```

`--show-config` pretty-prints the resolved config and highlights neph-managed lines.

## Agent Integration

| Agent | Mechanism | Policy engine |
|-------|-----------|---------------|
| Claude | `PreToolUse` hook → `cupcake eval --harness claude` | Cupcake |
| Cursor | hooks.json → `cupcake eval --harness cursor` | Cupcake |
| Gemini | `BeforeTool` hook → `neph integration hook gemini` | noop |
| Copilot | hooks.json → `cupcake eval --harness copilot` | Cupcake |
| Pi | Extension → Cupcake harness (legacy) | Cupcake |
| Amp | Terminal-only (hook integration pending) | noop |
| Goose, Codex, Crush | Terminal-only | noop |

## `neph review`

Editor abstraction for interactive code review. Called by Cupcake signals or
direct hook integrations.

**Protocol:**
- stdin: `{ "path": "/abs/path", "content": "proposed content" }`
- stdout: `{ "decision": "accept|reject|partial", "content": "...", "reason?": "..." }`
- Exit codes: `0` = accept/partial, `2` = reject, `3` = timeout

```sh
echo '{"path":"/tmp/f.lua","content":"hello"}' | neph review
```

## Cupcake policies

Rego policies in `.cupcake/policies/neph/`:
- `review.rego` — routes write/edit tools through interactive review
- `dangerous_commands.rego` — blocks rm -rf, force push, --no-verify
- `protected_paths.rego` — blocks writes to .env, credentials, SSH keys

Signals in `.cupcake/signals/`:
- `neph_review` — chains reconstruct + review
- `neph_reconstruct` — normalizes agent JSON to `{ path, content }`

Cupcake assets are installed when enabling a Cupcake-backed integration via
`neph integration toggle`.

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
