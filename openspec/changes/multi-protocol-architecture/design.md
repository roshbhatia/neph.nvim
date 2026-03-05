## Context

**Current State:**
- Python subprocess (shim.py) bridges pi extension ↔ Neovim via pynvim msgpack-rpc
- Pi's ExtensionAPI has NO built-in Neovim connection (no ctx.nvim) — shim IS the bridge
- Inline Lua strings passed through Python exec_lua — leaky, untestable
- Diff review works but is fragile: temp files, sleep-polling, no request correlation
- Terminal agents (claude, goose) just send text via multiplexer — simple and correct
- Dagger CI uses `nix-shell shell.nix` — should be flake-first with `nix develop`

**Research Findings:**
1. **pi-coding-agent**: ExtensionAPI is Neovim-agnostic. Provides `pi.on()`, `pi.registerTool()`, `ctx.ui.setStatus()`, `pi.exec()`. No Neovim bridge.
2. **opencode**: Also supports extensions, similar pattern — no built-in Neovim bridge
3. **claude code / amp**: Discover tools via PATH, call as executables with stdin/stdout
4. **codediff.nvim**: Read-only diff viewer — cannot replace our per-hunk accept/reject flow
5. **Neovim plugin ecosystem**: No plugins use Dagger; all use `rhysd/action-setup-vim` or AppImage. `mini.doc` is the idiomatic vimdoc generator. `lazy.minit` is the modern test bootstrap pattern.

**Key Insight:**
A shim process is the **universal adapter**. It serves both RPC agents (pi, opencode) that spawn it as a subprocess AND PATH agents (claude code, amp) that discover it as an executable tool.

**Constraints:**
- Neovim ≥ 0.10 required
- Node.js on PATH (already required for pi ecosystem)
- Must handle async interactive review without deadlocking in :terminal
- Unix philosophy: do one thing well, composable, text streams as interfaces
- Tests must pass in Dagger locally before pushing

## Goals / Non-Goals

**Goals:**
- **Universal bridge**: One CLI (`neph`) serves both RPC agents and PATH tools
- **Clean RPC boundary**: Lua dispatch facade — external code never writes inline Lua
- **Testable review**: Engine logic tested headless, UI tested manually
- **Robust async protocol**: Request IDs, atomic writes, notification-driven completion
- **Contract sync**: `protocol.json` validated by both Lua and TS tests
- **Flake-first CI**: `nix develop` provides all deps deterministically
- **Idiomatic docs**: `mini.doc` for vimdoc, `docs/*.md` for architecture

**Non-Goals:**
- Generic protocol framework (WebSocket, Script Protocol, Protocol Negotiation)
- Lifecycle hooks system (agents have their own event systems)
- Tool registry (we don't need to re-discover tools at runtime)
- Node client package as library (the CLI IS the interface)
- codediff.nvim integration (it can't do per-hunk accept/reject)
- Cross-language type codegen (contract tests are sufficient)
- Backward compatibility with shim.py (pre-1.0, clean break)

## Decisions

### 1. Universal CLI Called `neph`

**Decision:** Build a single Node/TS CLI that serves all external consumers:

```
CONSUMER A: RPC Agents (pi, opencode extensions)
  pi.ts:  spawn("neph", ["review", path], { stdin: content })
          → stdout JSON → ReviewEnvelope

CONSUMER B: PATH Tools (claude code, amp --ide)
  $ echo "proposed content" | neph review foo.ts
  → stdout: ReviewEnvelope JSON
```

**CLI Commands:**
```
neph review <path>    stdin=content, stdout=ReviewEnvelope JSON (interactive)
neph set <key> <val>  fire-and-forget (set vim.g global)
neph unset <key>      fire-and-forget
neph checktime        fire-and-forget (reload buffers)
neph close-tab        fire-and-forget
neph status           stdout=JSON connection info
neph spec             stdout=tool schema JSON (for PATH agent discovery)
```

**Contract:**
- stdout: machine-readable JSON only
- stderr: human-readable logs/errors
- stdin: content payloads (for review)
- Exit 0: success, non-zero: failure
- `NVIM_SOCKET_PATH` env var for Neovim connection (inherited or auto-discovered)

**Implementation:**
- TypeScript, bundled with esbuild to single file
- `@neovim/node-client` for msgpack-rpc to Neovim
- Transport layer injected as interface — unit tests use fake transport
- `#!/usr/bin/env node` shebang, symlinked to `~/.local/bin/neph`

**Rationale:**
- One bridge, two consumer types — unix philosophy
- Same ecosystem as pi extensions (TypeScript)
- esbuild bundle = single file, fast startup
- Injected transport = testable without spawning Neovim

**Alternatives considered:**
- ❌ **Direct Node RPC client inside pi**: Doesn't help PATH tools
- ❌ **Keep Python shim**: Unnecessary Python dependency
- ❌ **Go/Rust binary**: Bigger rewrite, revisit only if "no Node" becomes required

### 2. Lua RPC Dispatch Facade

**Decision:** One Lua module routes all external RPC calls. External code never writes inline Lua.

```lua
-- lua/neph/rpc.lua
local dispatch = {
  ["review.open"]   = function(p) return require("neph.api.review").open(p) end,
  ["status.set"]    = function(p) return require("neph.api.status").set(p) end,
  ["status.unset"]  = function(p) return require("neph.api.status").unset(p) end,
  ["buffers.check"] = function(p) return require("neph.api.buffers").checktime(p) end,
  ["tab.close"]     = function(p) return require("neph.api.buffers").close_tab(p) end,
}

function M.request(method, params)
  local handler = dispatch[method]
  if not handler then
    return { ok = false, error = { code = "METHOD_NOT_FOUND", message = method } }
  end
  local ok, result = pcall(handler, params or {})
  if not ok then
    return { ok = false, error = { code = "INTERNAL", message = result } }
  end
  return { ok = true, result = result }
end
```

**The neph CLI uses ONE constant Lua string:**
```typescript
const RPC_CALL = `return require("neph.rpc").request(...)`;
// Every command: nvim.executeLua(RPC_CALL, [method, params])
```

**Rationale:**
- Single RPC boundary — clean, auditable, versioned
- External code has zero Lua knowledge
- Dispatch table is the protocol definition
- Error normalization in one place

**Alternatives considered:**
- ❌ **Inline Lua per command**: Leaky, untypeable, breaks silently
- ❌ **Separate exec_lua calls per API function**: Same problem, scattered

### 3. Review Engine / UI Split

**Decision:** Separate pure review logic from Neovim UI:

```
REVIEW ENGINE  (lua/neph/api/review/engine.lua)
  Pure logic, testable with nvim --headless, no UI

  • compute_hunks(old_lines, new_lines) → hunk[]
  • apply_decisions(old_lines, new_lines, decisions) → final_content
  • build_envelope(decisions) → ReviewEnvelope
  • State machine: next, accept, reject, accept_all

REVIEW UI  (lua/neph/api/review/ui.lua)
  Thin Neovim adapter, tested manually

  • open_diff_tab(orig, proposed) → tab handles
  • Signs, virtual text, winbars
  • Snacks.picker.select loop for hunk decisions
  • Calls engine for state transitions + envelope
  • Writes result + rpcnotify on completion
```

**Rationale:**
- Engine testable with plenary in headless nvim — no UI mocking
- UI layer is thin — only wires Neovim primitives to engine calls
- Current review UX (vimdiff + Snacks picker + per-hunk signs) preserved
- codediff.nvim evaluated and rejected (no per-hunk decision callback)

### 4. Hardened Async Review Protocol

**Decision:** Request IDs + atomic writes + notification-driven completion:

```
  neph CLI                          Neovim (rpc.lua → review)

  1. Generate request_id (uuid)
  2. Create result_path

     exec_lua(RPC_CALL, {
       method: "review.open",
       request_id: "abc-123",
       result_path: "/tmp/neph-...",
       channel_id: N,
       path, content
     })
     ─────────────────────────────▶
                                     opens diff tab (non-blocking)
     returns immediately

     ... user reviews hunks ...

                                     engine builds envelope
                                     write result_path.tmp
                                     rename → result_path (atomic)
     ◀─── rpcnotify(channel,
          "neph:review_done",
          { request_id: "abc-123" })

  3. Read result_path
  4. Print envelope JSON to stdout
  5. Cleanup + exit 0
```

**Three improvements over current shim.py:**
1. **Request ID**: Prevents cross-talk between concurrent reviews
2. **Atomic write**: `rename()` instead of hoping file is fully written
3. **Notification-driven**: `onNotification` callback, no `time.sleep(0.1)` polling

### 5. Transport Interface Injection (Testability)

**Decision:** The neph CLI's Neovim transport is an injected interface:

```typescript
interface NvimTransport {
  executeLua(code: string, args: unknown[]): Promise<unknown>;
  onNotification(event: string, handler: (args: unknown[]) => void): void;
  close(): Promise<void>;
}
```

- **Production**: `SocketTransport` wraps `@neovim/node-client` over Unix socket
- **Tests**: `FakeTransport` records calls and returns scripted responses

**Rationale:**
- Unit tests run in vitest without spawning Neovim — fast, deterministic
- Integration tests (few) use real headless Neovim over socket
- Matches how pi.test.ts already works (mocking spawn, not Neovim)

### 6. Contract Sync via `protocol.json`

**Decision:** Keep Lua ↔ TS RPC contract in sync without codegen:

```json
{
  "version": "neph-rpc/v1",
  "methods": {
    "review.open": {
      "params": ["request_id", "result_path", "channel_id", "path", "content"],
      "async": true
    },
    "status.set": { "params": ["name", "value"] },
    "status.unset": { "params": ["name"] },
    "buffers.check": { "params": [] },
    "tab.close": { "params": [] }
  }
}
```

- Lua contract test: asserts every method in dispatch table exists in `protocol.json`
- TS contract test: asserts every client method references a known method in `protocol.json`
- Human-readable docs in `docs/rpc-protocol.md`

**Rationale:**
- No codegen pipeline to maintain
- Both sides validated independently
- Contract drift caught before merge
- Revisit codegen only if method count exceeds ~20

**Alternatives considered:**
- ❌ **Cross-language type generation**: Heavy machinery for 5 methods
- ❌ **No contract validation**: Silent drift between Lua and TS

### 7. Flake-First Dagger CI

**Decision:** Migrate Dagger pipeline from `nix-shell shell.nix` to `nix develop`:

```typescript
const base = client
  .container()
  .from("nixos/nix")
  .withEnvVariable("NIX_CONFIG", "experimental-features = nix-command flakes")
  .withDirectory("/app", src, { exclude: [".git", "node_modules", ".fluentci"] })
  .withWorkdir("/app");

const lint = base.withExec(["nix", "develop", "--no-write-lock-file", "-c", "task", "lint"]);
const test = base.withExec(["nix", "develop", "--no-write-lock-file", "-c", "task", "test"]);
```

**Rationale:**
- `flake.lock` pins everything — no channel drift
- `--no-write-lock-file` prevents accidental lock updates in CI
- Single source of truth for dev environment
- `nix develop -c` is the idiomatic pattern

**Alternatives considered:**
- ❌ **nix-shell with channels**: Non-deterministic, legacy pattern
- ❌ **No Nix in CI (AppImage + clone deps)**: Ecosystem norm but loses our flake's determinism

### 8. Documentation Strategy

**Decision:** Two layers of docs:

**Generated vimdoc (mini.doc):**
- `doc/neph.txt` — generated from EmmyLua annotations in `lua/neph/`
- API reference for `:help neph`
- Generated in CI, committed to repo (mini.nvim pattern)

**Architecture docs (Markdown, alongside code):**
- `docs/architecture.md` — module boundaries, data flow, integration patterns
- `docs/rpc-protocol.md` — method catalog, payload shapes, versioning
- `docs/testing.md` — how tests are structured, how to run locally/CI
- High-impact, maintained by humans, no generation

**Rationale:**
- `mini.doc` is the idiomatic Neovim vimdoc generator
- Markdown docs live in `docs/`, render on GitHub, high-impact
- No over-engineering: two clear layers with distinct purposes

### 9. Testing Philosophy

**Decision:** Idiomatic tests, no ceremony:

- Tests read like behavior descriptions
- No comments explaining obvious assertions
- No bespoke test DSLs or deep helper abstractions
- Table-driven tests only when they genuinely reduce repetition
- Mock at boundaries (transport, filesystem), not internal modules
- `---@diagnostic disable` not needed — configure luacheck globals properly

**Test layers:**

| Layer | Runner | What | How |
|-------|--------|------|-----|
| Lua unit | plenary/busted, nvim --headless | Review engine, RPC dispatch, API modules | Pure function calls, no UI |
| CLI unit | vitest | neph commands, transport protocol | Fake transport, no Neovim |
| Contract | both | protocol.json matches dispatch + client | JSON schema validation |
| CLI integration | vitest | End-to-end RPC over socket | Real headless Neovim, few tests |
| Pi adapter | vitest | pi.ts event handling | Mock neph spawn (existing pattern) |
| UI | manual | Review flow, signs, picker | Human verification |

## Implementation Plan

### Phase 1: Lua API Layer + Review Engine Split
1. Create `lua/neph/api/review/engine.lua` — extract pure logic from `open_diff.lua`
2. Create `lua/neph/api/review/ui.lua` — thin adapter using engine
3. Create `lua/neph/api/status.lua`, `lua/neph/api/buffers.lua`
4. Create `lua/neph/rpc.lua` — dispatch facade
5. Unit tests for engine and rpc dispatch (plenary/busted)

### Phase 2: neph CLI
1. Create `tools/neph-cli/` — TypeScript CLI with transport interface
2. Implement commands: review, set, unset, checktime, close-tab, status, spec
3. Hardened review protocol: request_id, atomic write, notification-driven
4. Unit tests with fake transport (vitest)
5. Integration tests with headless Neovim (vitest, few)

### Phase 3: Pi Adapter + Migration
1. Refactor `tools/pi/pi.ts` — replace shim spawn with neph spawn
2. Update `tools.lua` — symlink neph instead of shim
3. Delete `tools/core/shim.py`, `tools/core/lua/`, Python test infra
4. Update pi.test.ts for new CLI contract

### Phase 4: Contract + CI + Docs
1. Create `protocol.json` + contract tests (both Lua and TS)
2. Migrate `.fluentci/ci.ts` to `nix develop`
3. Update `flake.nix` — add mini.doc, remove Python/flake8
4. Generate `doc/neph.txt` with mini.doc
5. Write `docs/architecture.md`, `docs/rpc-protocol.md`, `docs/testing.md`
6. Update Taskfile.yml — new test/lint targets

## Open Questions

1. **Socket auto-discovery**: Keep the glob-based discovery from shim.py or simplify to `$NVIM_SOCKET_PATH` only?
2. **Dry-run mode**: Keep `NEPH_DRY_RUN=1` for offline auto-accept? (Useful for CI testing of agents)
3. **neph CLI startup time**: Is esbuild-bundled Node fast enough? Measure before optimizing.
