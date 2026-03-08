## Why

Current architecture sends text to agents via terminal/multiplexer, and uses a Python subprocess (shim.py + pynvim) as the Neovim RPC bridge for agents like pi. The shim works but adds a Python dependency, uses inline Lua strings for RPC calls, and has a fragile review protocol (temp files, sleep-polling). We need a clean, universal bridge between external programs and Neovim that serves both RPC-capable agents and PATH-discovered tools.

## What Changes

- **BREAKING**: Python shim (`tools/core/shim.py`) replaced by Node/TS CLI (`neph`)
- **New**: `lua/neph/rpc.lua` — single dispatch facade for all external RPC calls
- **New**: Review engine/UI split — testable pure logic separated from Neovim UI
- **New**: Hardened async review protocol — request IDs, atomic writes, notification-driven
- **New**: `neph spec` command — self-describing tool schema for PATH agent discovery
- **New**: `protocol.json` — canonical RPC contract, validated by both Lua and TS tests
- **Simplified**: `tools/pi/pi.ts` — thin adapter calling `neph` CLI, no inline Lua
- **Removed**: Python shim subprocess model
- **Removed**: Inline Lua strings in TypeScript

## Capabilities

### New Capabilities

- `neph-cli`: Universal Node/TS bridge CLI — serves both RPC agent extensions (pi, opencode) and PATH-discovered tools (claude code, amp)
- `rpc-dispatch`: Single Lua dispatch facade (`lua/neph/rpc.lua`) routing method+params to API modules
- `review-engine`: Pure Lua review logic (hunks, decisions, envelope construction) — testable headless
- `testing-infrastructure`: Transport injection for CLI tests, contract tests for RPC sync, flake-first Dagger CI

### Modified Capabilities

- `review-ui`: Existing vimdiff + Snacks picker flow preserved, refactored into thin adapter over engine

## Impact

**Code Changes:**
- New: `tools/neph-cli/` — Node/TS CLI, esbuild-bundled, `@neovim/node-client` for msgpack-rpc
- New: `lua/neph/rpc.lua` — dispatch table routing methods to `lua/neph/api/` modules
- New: `lua/neph/api/review/engine.lua` — pure logic: hunks, decisions, envelope construction
- New: `lua/neph/api/review/ui.lua` — thin Neovim UI adapter (signs, picker, vimdiff)
- New: `lua/neph/api/status.lua` — set/unset vim.g globals
- New: `lua/neph/api/buffers.lua` — checktime, tab management
- New: `protocol.json` — canonical RPC method catalog, validated by contract tests
- New: `docs/rpc-protocol.md` — human-readable protocol documentation
- New: `docs/architecture.md` — module boundaries, data flow
- Updated: `.fluentci/ci.ts` — `nix develop` instead of `nix-shell`
- Updated: `flake.nix` — add mini.doc for vimdoc generation
- Simplified: `tools/pi/pi.ts` — calls `neph` CLI, no shimRun/shimQueue, no inline Lua
- Remove: `tools/core/shim.py`, `tools/core/lua/`, Python test infrastructure

**Integration Patterns:**

**RPC Agents (pi, opencode) — spawn neph as subprocess:**
```typescript
const result = await neph(["review", filePath], content);
// result is ReviewEnvelope JSON — no Lua anywhere in pi.ts
```

**PATH Agents (claude code, amp) — discover neph on PATH:**
```bash
$ echo "proposed content" | neph review path/to/file.ts
# stdout: {"schema":"review/v1","decision":"accept","content":"..."}
```

**Terminal Agents (goose, gemini) — no neph involvement:**
```lua
session.send(agent, context.expand(prompt))
```

**Dependencies:**
- Add: `@neovim/node-client`, `esbuild`
- Add: `mini.doc` (vimdoc generation, in flake.nix devShell)
- Keep: Node.js (already required for pi ecosystem)
- Remove: Python, pynvim, click, uv, pytest, flake8
