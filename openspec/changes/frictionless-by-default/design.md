## Context

The composable-integrations work landed an internal pipeline (adapter → policy engine → review provider → formatter) that handles the *decision* layer well. The remaining friction is at the *connection* and *context* layers:

1. **Connection**: every agent integration reinvents transport. claude uses cupcake hooks; pi/gemini use the bus; opencode uses SSE. Meanwhile, `claudecode.nvim` and `opencode.nvim` already implement WebSocket/MCP and HTTP/SSE end-to-end, including lockfile discovery, selection broadcasting, and visible-files tracking. We are duplicating their work.

2. **Context**: neph has a rich placeholder system (`+selection`, `+file`, `+diagnostics`, …) but it only fires when the user types a placeholder into the prompt. The agent has no awareness of editor state outside that explicit pull. This is the single biggest UX gap vs. claudecode/amp/opencode.

3. **Defaults**: `gate = "normal"` means every agent write opens a review UI tab. claude launches with `--permission-mode plan`. The user must intervene constantly. The desired posture is "trust by default, intervene by keymap."

## Goals / Non-Goals

**Goals:**
- Let `claudecode.nvim` and `opencode.nvim` own protocol/transport/broadcast for their respective agents.
- Provide ambient context to *all* agents (not just peer-mode) via a single file path and one CLI command.
- Default to fully-open: gate bypassed, claude permissions skipped.
- Keep all existing safety mechanisms intact and one keymap away.
- Backwards-compatible: existing agent definitions, hook agents, terminal agents, extension agents continue to work unchanged.

**Non-Goals:**
- Rewriting hook-based claude or pi/gemini extension agents. These keep working as-is. Peer mode is opt-in via separate agent definitions.
- Vendoring `claudecode.nvim` or `opencode.nvim` source. They are optional peer plugins.
- Replacing the cupcake policy engine or review provider opt-in (those layers are unchanged).
- Implementing a WebSocket server inside neph itself. Peer plugins handle that.

## Decisions

### 1) Peer plugins as optional dependencies, not hard requires

**Decision:** `claudecode.nvim` and `opencode.nvim` are loaded via `pcall(require, ...)` inside the relevant peer adapter. If absent, the adapter logs a one-time setup notice and the agent reports as unavailable; the rest of neph functions normally.

**Why:** Users who don't use Claude Code or OpenCode shouldn't have to install two extra plugins. Peer adapters degrade gracefully.

**Alternatives considered:**
- Hard `dependencies` in plugin spec: rejected — penalises users who only use one agent.
- Vendoring source: rejected — maintenance burden, divergence from upstream, no shared bugfixes.

### 2) `type = "peer"` agent variant

**Decision:** Extend the agent-type enum to `{hook, terminal, extension, peer}`. Peer agents add a `peer` sub-table:

```lua
{
  name = "claude-peer",
  label = "Claude (peer)",
  icon = "",
  cmd = "claude",                     -- still required for picker text
  type = "peer",
  peer = {
    kind = "claudecode",              -- selects the adapter module
    override_diff = true,             -- intercept openDiff via neph review queue
  },
}
```

`session.open()` checks `agent.type` and dispatches to `peers/<kind>.lua` instead of the configured backend. Hook and terminal agents stay on their existing path.

**Why:** Reuses the existing dispatch shape (`hook` vs `extension` already branches in `session.lua`). Adding a fourth branch is minimally invasive.

**Alternatives considered:**
- A new `adapter` field on every agent: rejected — too disruptive, every existing definition would need migration.
- Auto-detect peer plugin presence and silently switch claude to peer mode: rejected — magic; surprising for users who chose hook mode deliberately.

### 3) openDiff override routes to neph review queue

**Decision:** When a `claudecode` peer agent has `peer.override_diff = true`, the adapter monkey-patches `claudecode.tools.handlers.openDiff` after `claudecode.setup()` runs. The replacement handler captures the proposed content, enqueues a review through `neph.internal.review_queue`, and resolves the deferred MCP response based on user accept/reject.

**Why:** This is the single point of integration that gives the user "blocking diff approval through neph's UI." Without it, claudecode shows its own vimdiff and the gate never fires.

**Alternatives considered:**
- File-watcher-only review (skip openDiff entirely): rejected — claude has already decided to write by the time the watcher fires; we lose the "approve before write" flow that's the whole point of openDiff.
- Submit a public override API to claudecode upstream: pursued in parallel as a follow-up; monkey-patch is fine for now and isolates the brittleness to one file.

### 4) Auto-context broadcast file at `stdpath("state")/neph/context.json`

**Decision:** A single autocommand-driven broadcaster writes the current editor snapshot to one JSON file. Schema:

```json
{
  "ts": 1730000000000,
  "session": "<nvim-pid-or-server-id>",
  "cwd": "/path/to/repo",
  "buffer": {
    "uri": "file:///path/to/foo.lua",
    "language": "lua",
    "cursor": {"line": 42, "character": 7},
    "selection": {"text": "...", "range": {...}}
  },
  "visible": ["file:///path/to/foo.lua", "file:///path/to/bar.ts"],
  "diagnostics": {
    "file:///path/to/foo.lua": [{"severity": "error", "message": "...", "range": {...}}]
  }
}
```

Triggers (debounced 50ms): `CursorMoved`, `CursorMovedI`, `BufWinEnter`, `BufWinLeave`, `WinClosed`, `DiagnosticChanged`, `DirChanged`. Source-window filter mirrors `lua/neph/internal/context.lua` (skip terminals, floats, NvimTree, etc.).

**Why:** A single file at a discoverable path is the lowest-common-denominator integration surface. Every agent — including pure CLI tools that don't speak any of neph/claudecode/opencode protocols — can read it. No port discovery, no socket handshake.

**Alternatives considered:**
- Unix socket / named pipe: rejected — complicates CLI tooling, harder to debug, no advantage over a file given the write rate.
- Per-agent broadcast files: rejected — same data, N copies.
- Embed snapshot inside neph RPC: already exists for placeholder expansion; this complements it for agents that don't speak neph RPC.

### 5) `gate = "bypass"` and `--dangerously-skip-permissions` as defaults

**Decision:** Flip `config.defaults.gate = "bypass"` (currently `"normal"`). Update `lua/neph/agents/claude.lua` to drop `--permission-mode plan` and add `--dangerously-skip-permissions`. Other agents' default flags reviewed for similar adjustments where safe.

**Why:** The user explicitly wants frictionless. The review pipeline still installs; users opt in by cycling the gate (`<leader>jg`) or registering a per-project neoconf override (`neph.gate = "normal"`).

**Alternatives considered:**
- Keep current conservative defaults, document opt-out: rejected — directly contradicts the stated goal.
- Default to `"hold"`: rejected — neither fully open nor enforcing; worst of both.

### 6) Peer adapter contract surface

The adapter module exposes the minimum to plug into `session.lua`:

```lua
M.is_available()                       -- did the peer plugin require() succeed?
M.open(agent, opts)                    -- analogous to backend.open; returns term_data-shaped table
M.send(agent, text, opts)              -- delegates to peer plugin's send mechanism
M.kill(agent)                          -- tear down the peer-managed session
M.is_visible(agent)                    -- for picker UX
M.focus(agent)                         -- focus the agent's UI
M.hide(agent)                          -- hide the agent's UI
```

Adapters are NOT backends — they don't go through the backend dispatch. `session.open()` calls `peers.resolve(agent).open(agent, opts)` directly when `agent.type == "peer"`.

## Risks / Trade-offs

- **[Risk] claudecode.nvim's tool registry shape is internal API** → Mitigation: thin override module with version-pinned smoke test in CI; submit upstream PR for `register_tool(name, handler, override = true)`. If claudecode changes shape, the adapter's `open()` returns `is_available = false` with a clear error.
- **[Risk] Two diff systems running side-by-side (claudecode's vimdiff + neph's review)** → Mitigation: when override_diff = true, the patch removes claudecode's diff handler entirely; users see only neph's UI.
- **[Risk] Auto-context file leaks paths to disk** → Mitigation: written to `stdpath("state")` (XDG state dir, user-owned, 0700); not synced to cloud profiles by default. Document as a debug surface; no secret material is captured.
- **[Risk] Default gate=bypass means destructive writes proceed unprompted** → Mitigation: prominent README callout; `<leader>jg` cycles to `normal` instantly; per-project neoconf override; `:NephGate normal` command.
- **[Risk] Existing claude users surprised by `--dangerously-skip-permissions`** → Mitigation: this is a behavior change; document in CHANGELOG. Users who want plan mode override `args` in their setup.
- **[Risk] Peer adapter divergence — claudecode/opencode evolve, our adapter rots** → Mitigation: minimal surface area (six functions), CI smoke test runs against pinned plugin versions.

## Migration Plan

1. Land scaffolding: contract change (`type = "peer"`), peers/init.lua registry, broadcaster module — no behavior change for existing users.
2. Land "open by default": flip gate default + claude args. This is the user-visible behavior change; ship behind a CHANGELOG note.
3. Land claudecode peer adapter + new `claude-peer` agent definition. Users opt in by adding `require("neph.agents.claude-peer")` to their agents list.
4. Land opencode peer adapter + new `opencode-peer` agent definition.
5. Land `neph context current` CLI command.
6. README + manual test plan for each agent type in wezterm.

Rollback: each step is independently revertable. The peer adapters are opt-in; the auto-broadcaster is config-gated (`context_broadcast.enable = true` default, but flag exists).

## Open Questions

- Should `--dangerously-skip-permissions` be the default for `claude-peer` only, or also for the existing hook-mode `claude`? Current plan: both, since both run under neph's gate. Revisit if signal/noise from incident reports changes.
- Should the broadcast file include shell clipboard contents? The user's message mentioned clipboard sharing. Tentative: NO by default — clipboard often contains secrets — but expose `context_broadcast.include_clipboard = true` as opt-in.
- Should opencode peer adapter call `opencode.prompt()` for `session.send()`, or use `opencode.command()`? Both work; `prompt()` matches our ask/fix/comment shape best.
