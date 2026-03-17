## Why

The current gate system has three separate integration models (hook agents, extension agents, terminal agents) with divergent failure semantics, result routing, and error handling. Pi's extension model queues null reviews when its socket dies. Gemini requires a bespoke MCP companion sidecar. Each new agent means a new adapter with unique failure modes. The review engine and UI are solid — the plumbing around them is what's broken.

The fix is not to patch each path. The fix is to have **one path**. Cupcake (EQTY Lab's policy enforcement layer) becomes the sole integration layer between agents and neph. No agent ever talks to Neovim directly. No fallbacks, no alternative paths, no fail-open. Cupcake or nothing.

## What Changes

- **Cupcake is the ONLY integration layer** — Every agent hook (Claude `PreToolUse`, Gemini `BeforeTool`, Pi `tool_call`) points to `cupcake eval`. Cupcake evaluates deterministic Rego policies and invokes `neph-cli` as a signal for interactive review. No agent ever touches a Neovim socket.
- **neph-cli becomes an editor abstraction** — Called only by Cupcake signals, never by agents. Speaks one protocol: `{ path, content }` in, `{ decision, content }` out. No `--agent` flag, no per-agent formatters. Swappable to other editors (VS Code, Zed) by replacing the transport layer.
- **Cupcake Pi harness** — Pi extension that intercepts `tool_call` events, calls `cupcake eval --harness pi`. Cupcake is required, not optional. No fallback to direct neph-cli.
- **All hooks point to Cupcake** — `.claude/settings.json` PreToolUse → `cupcake eval --harness claude`. `.gemini/settings.json` BeforeTool → `cupcake eval --harness gemini`. Agent-specific normalization and response formatting is Cupcake's job, not neph-cli's.
- **No fail-open** — If Cupcake fails, the action is rejected. If Neovim is unreachable, the action is rejected. No silent auto-accept.
- **Remove per-agent normalizers from neph-cli** — **BREAKING** — neph-cli no longer knows about Claude, Gemini, or any agent's JSON format. It receives pre-normalized `{ path, content }` from Cupcake signals.
- **Remove NephClient SDK** (`tools/lib/neph-client.ts`) — **BREAKING** — persistent socket connection model, channel registration, notification-based result routing all removed.
- **Remove bus system** (`lua/neph/internal/bus.lua`) — **BREAKING** — channel registry, health check timer, prompt delivery all removed.
- **Remove gate.ts** — **BREAKING** — replaced by Cupcake interception.
- **Remove Gemini companion sidecar** — **BREAKING** — replaced by Gemini CLI's native hooks through Cupcake.
- **Cupcake policy suite** — Rego policies for deterministic blocking (dangerous commands, protected paths) plus review-triggering policy that routes write/edit tools through the `neph_review` signal.
- **Comprehensive test coverage** — neph-cli protocol tests, Cupcake signal integration tests, Rego policy tests, per-agent E2E tests, contract tests.

## Capabilities

### New Capabilities

- `cupcake-integration`: Cupcake as sole integration layer — all agent hooks point to `cupcake eval`, Cupcake signals call neph-cli, Cupcake handles agent-specific normalization and response formatting
- `cupcake-pi-harness`: Cupcake harness for Pi agent — Pi extension that bridges Pi's `tool_call` events to `cupcake eval` (required, no fallback)
- `neph-review-command`: Simplified `neph-cli review` — editor abstraction with one protocol (`{ path, content }` in, `{ decision, content }` out), no agent awareness
- `cupcake-policy-suite`: Rego policy files for deterministic blocking and review-triggering — configurable per-project and global

### Modified Capabilities

- `review-protocol`: Review orchestration accepts input from neph-cli via RPC. No temp file, no notification-based result routing.
- `review-ui`: Review UI unchanged in behavior, opened by neph-cli via Neovim RPC.
- `tool-install`: Tool installation adds Cupcake init + policy deployment, removes Pi extension/Gemini companion builds. Cupcake is required.
- `neph-cli`: CLI simplifies — `gate` subcommand removed, `review` subcommand speaks one protocol, no `--agent` flag, no per-agent formatters.
- `rpc-dispatch`: RPC methods `bus.register` and `review.pending` removed. `review.open` simplified.
- `testing-infrastructure`: Test suite restructured — neph-cli protocol tests, Cupcake signal tests, Rego policy tests, per-agent E2E tests.

## Impact

- **Removed files**: `tools/lib/neph-client.ts`, `lua/neph/internal/bus.lua`, `tools/neph-cli/src/gate.ts`, `tools/neph-cli/src/normalizers/` (per-agent normalizers), `tools/gemini/src/companion.ts`, `tools/gemini/src/diff_bridge.ts`
- **Major rewrites**: `tools/neph-cli/src/review.ts` (simplify to one protocol), `tools/pi/pi.ts` (becomes Cupcake harness), agent definitions
- **Modified**: `lua/neph/api/review/init.lua`, `lua/neph/rpc.lua`, `protocol.json`, `lua/neph/init.lua`, `Taskfile.yml`
- **New files**: `.cupcake/` policy directory, `tools/pi/cupcake-harness.ts`, Cupcake harness configs
- **Required dependencies**: Cupcake CLI (`cupcake eval`), OPA (for policy compilation)
- **Breaking**: All agents must go through Cupcake. No direct hook-to-neph-cli path. No fail-open.
