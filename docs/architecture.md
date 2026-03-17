# Neph Architecture

Neph.nvim is a Neovim integration layer for AI agents. It provides interactive code review, terminal management, and status bridging between agents and Neovim.

## Core Principle

**Cupcake is the sole integration layer.** No agent ever talks to Neovim directly. All agent hooks point to `cupcake eval`. Cupcake evaluates deterministic policies, then invokes `neph-cli` as a signal for interactive review.

```
Agent ──▶ Cupcake ──▶ neph-cli ──▶ Neovim
                                      │
Agent ◀── Cupcake ◀── neph-cli ◀──────┘
```

## Component Boundaries

### 1. Cupcake (Policy + Routing Layer)

Every agent hook points to `cupcake eval --harness <agent>`. Cupcake:
- Evaluates deterministic Rego/Wasm policies (< 1ms) — blocks dangerous commands, protects sensitive paths
- Invokes the `neph_review` signal for write/edit tools
- Handles agent-specific JSON normalization and response formatting
- Returns decisions in the agent's expected format

Policies live in `.cupcake/policies/neph/`:
- `review.rego` — routes write/edit tools through interactive review
- `dangerous_commands.rego` — blocks rm -rf, force push, --no-verify
- `protected_paths.rego` — blocks writes to .env, credentials, SSH keys

### 2. neph-cli (Editor Abstraction)

A Node.js CLI (`tools/neph-cli/`) that bridges Cupcake signals to Neovim. Speaks one protocol:
- **stdin**: `{ path: string, content: string }`
- **stdout**: `{ decision: "accept"|"reject"|"partial", content: string, reason?: string }`
- **Exit codes**: 0 = accept/partial, 2 = reject, 3 = timeout

neph-cli has **zero agent awareness** — no `--agent` flag, no per-agent normalizers or formatters. It knows about Neovim, not about agents. Swappable to other editors by replacing the transport layer.

Other commands: `set`, `unset`, `get`, `checktime`, `close-tab`, `ui-select`, `ui-input`, `ui-notify`.

### 3. RPC Dispatch Facade (`lua/neph/rpc.lua`)

Single Lua module routing all incoming RPC to internal API modules. Handles method routing, error normalization, pcall-wrapped execution.

### 4. API Modules (`lua/neph/api/`)

Stateless modules implementing capabilities:
- `review/`: Core diff review logic and UI
- `status.lua`: Global state management (`vim.g`)
- `buffers.lua`: Buffer and tab operations
- `ui.lua`: Selection, input, notification dialogs

### 5. Review Engine vs. UI

The review system is split into two layers:
- **Engine** (`lua/neph/api/review/engine.lua`): Pure logic for hunk computation and decision application. Testable in headless Neovim.
- **UI** (`lua/neph/api/review/ui.lua`): Vimdiff tab with per-hunk accept/reject keymaps, signs, winbar, and help popup.

### 6. Cupcake Signals (`.cupcake/signals/`)

- `neph_review` — Wrapper script that chains reconstruction + interactive review:
  1. Pipes Cupcake event JSON through `neph_reconstruct`
  2. Pipes the resulting `{ path, content }` to `neph-cli review`
  3. Returns `{ decision, content }` for Rego policy consumption
- `neph_reconstruct` — Extracts `{ path, content }` from agent tool JSON. For edit tools, reads the file and applies old_str/new_str replacement.

## Architecture Diagram

```
┌─────────────┐     ┌──────────────────────────┐     ┌───────────┐     ┌─────────┐
│   Agents    │────▶│        Cupcake           │────▶│ neph-cli  │────▶│ Neovim  │
│             │◀────│                          │◀────│           │◀────│ (neph)  │
│ Claude      │     │  Rego/Wasm policies      │     │ review    │     │ vimdiff │
│ Gemini      │     │  Signals:                │     │ set/unset │     │ status  │
│ Pi          │     │    neph_review            │     │ checktime │     │ ui.*    │
│ OpenCode    │     │    neph_reconstruct       │     │           │     │         │
│ Amp (soon)  │     │                          │     │           │     │         │
└─────────────┘     └──────────────────────────┘     └───────────┘     └─────────┘
```

## Data Flow: Interactive Review

1. Agent proposes a file write/edit. Agent's hook fires `cupcake eval --harness <agent>`.
2. Cupcake evaluates deterministic policies (block dangerous ops, protect paths).
3. If write/edit tool: `neph_review` signal fires.
4. Signal runs `neph_reconstruct` to normalize agent JSON → `{ path, content }`.
5. Signal pipes `{ path, content }` to `neph-cli review`.
6. neph-cli connects to Neovim via `$NVIM` socket, calls `review.open` RPC.
7. Neovim opens vimdiff tab. User makes per-hunk accept/reject decisions.
8. neph-cli returns `{ decision, content }` on stdout.
9. Rego policy reads signal result, emits `allow` / `modify(updated_input)` / `deny`.
10. Cupcake returns decision to agent in agent-specific format.

### Outside Neovim (agent not in :terminal)

When no editor is reachable (`$NVIM` not set):
- Deterministic policies still enforce (block rm -rf, protect .env)
- `neph-cli review` returns `{ decision: "accept" }` (fail-open)
- The user opted out of interactive review by running outside Neovim

## Agent Integration

| Agent | Hook | Cupcake Harness | Status |
|-------|------|----------------|--------|
| Claude | `PreToolUse` → `cupcake eval --harness claude` | Native | Active |
| Gemini | `BeforeTool` → `cupcake eval --harness gemini` | Native | Active |
| Pi | `tool_call` → `cupcake eval --harness pi` | Custom extension | Active |
| OpenCode | Plugin → `cupcake eval --harness opencode` | Native | Active |
| Amp | — | Pending upstream | Terminal-only |
| Goose, Codex, Crush | — | — | Terminal-only |

## Protocols

- **Neovim RPC**: Standard msgpack-rpc over Unix sockets (`$NVIM`).
- **Neph RPC**: Custom method+params contract defined in `protocol.json`.
- **Neph CLI Protocol**: `{ path, content }` → `{ decision, content, reason? }` via stdin/stdout.
- **Cupcake**: Rego policies + signals, stdin/stdout JSON per harness.
