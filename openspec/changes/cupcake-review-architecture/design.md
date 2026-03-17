## Context

neph.nvim currently intercepts AI agent file mutations through three divergent paths with unique failure modes. The review engine and UI work well. The plumbing is what's broken.

The new architecture has exactly one path:

```
Agent ──▶ Cupcake ──▶ neph-cli ──▶ Neovim
                                      │
Agent ◀── Cupcake ◀── neph-cli ◀──────┘
```

Cupcake is the sole integration layer. neph-cli is an editor abstraction. Agents never see Neovim.

## Goals / Non-Goals

**Goals:**

- One path for all agents — every file mutation flows through Cupcake, no exceptions
- Deterministic policy enforcement — dangerous operations blocked before review (Rego/Wasm, < 1ms)
- Interactive hunk-by-hunk review preserved — the existing vimdiff UX stays
- neph-cli as a swappable editor abstraction — one protocol, no agent awareness
- Fail-open when no editor is reachable — deterministic policies still enforce, review gracefully skipped
- Comprehensive test coverage at every layer

**Non-Goals:**

- Replacing the review engine or UI — `engine.lua` and `ui.lua` are kept as-is
- Supporting agents without hooks or extension APIs — terminal-only agents remain terminal-only
- Building an MCP server — Cupcake is the integration layer, not MCP
- Cupcake Watchdog (LLM-as-Judge) — deterministic Rego policies only for now

## Decisions

### 1. Cupcake is the ONLY integration layer — no exceptions

**Decision**: Every agent hook points to `cupcake eval`. No agent ever calls neph-cli directly. No fallback path exists.

**Alternatives rejected**:
- *Cupcake optional, neph-cli as direct hook target*: Creates two paths with divergent failure modes — exactly the problem we're solving.
- *Cupcake for policy only, neph-cli for review*: Still two paths. If neph-cli can be called directly, someone will, and we're back to maintaining two integration models.

**Rationale**: One path means one set of failure modes, one test surface, one mental model. The cost is requiring Cupcake as a dependency. The benefit is eliminating an entire class of bugs.

### 2. neph-cli speaks one protocol, has no agent awareness

**Decision**: neph-cli receives `{ path: string, content: string }` on stdin, returns `{ decision: "accept"|"reject"|"partial", content: string, reason?: string }` on stdout. No `--agent` flag. No per-agent normalizers. No per-agent response formatters.

**Alternatives rejected**:
- *Per-agent normalizers in neph-cli*: Makes neph-cli grow linearly with agents. Cupcake already normalizes — doing it again is redundant.
- *Per-agent response formatters*: Agent-specific response formats (Claude's `hookSpecificOutput`, Gemini's `decision` field) are Cupcake's harness responsibility, not neph-cli's.

**Rationale**: neph-cli is an editor abstraction. It knows about Neovim, not about agents. This makes it testable in isolation and swappable to other editors. Agent-specific logic lives entirely in Cupcake's harness layer.

### 3. Agent-specific normalization lives in Cupcake

**Decision**: Cupcake's harness-specific preprocessing extracts `{ path, content }` from agent-specific JSON before passing it to the `neph_review` signal. Edit reconstruction (reading current file, applying old_str/new_str) happens in a Cupcake signal that runs before `neph_review`.

**How this works per agent**:
- **Claude**: Cupcake's Claude harness receives `{ tool_name: "Write", tool_input: { file_path, content } }`. A preprocessing signal or inline Rego extracts path/content and passes to `neph_review`.
- **Gemini**: Same pattern with `{ tool_name: "write_file", tool_input: { filepath, content } }`.
- **Pi**: The Pi Cupcake harness extension serializes Pi's `tool_call` event into Cupcake's format before calling `cupcake eval`.

### 4. Fail-open when no editor is reachable

**Decision**: If neph-cli can't reach Neovim (no `$NVIM`, no `$NVIM_SOCKET_PATH`), it returns `{ decision: "accept" }` (fail-open) with a stderr warning. Deterministic Rego policies (dangerous commands, protected paths) still evaluate and block regardless — they don't need Neovim. Only the interactive review is skipped.

This handles the critical scenario: **agent spawned outside Neovim**. A user runs Claude Code from a regular terminal, not inside `:terminal`. The hook fires, Cupcake evaluates, but neph-cli can't find an editor. The correct behavior is:

```
Agent outside Neovim:
  Hook → Cupcake → deterministic policies still block rm -rf, .env writes
                 → neph_review signal → neph-cli → no socket → fail-open accept
                 → Cupcake returns allow (policy permitted, no review available)

Agent inside Neovim terminal:
  Hook → Cupcake → deterministic policies block dangerous ops
                 → neph_review signal → neph-cli → $NVIM set → vimdiff review
                 → Cupcake returns allow/modify/deny based on review
```

**Rationale**: If there's no editor, there's nothing to review in. The user chose to run outside Neovim — they've opted out of interactive review. But they haven't opted out of policy enforcement: `rm -rf`, `.env` writes, force-push are still blocked by Rego policies that don't need an editor at all.

### 5. Pi harness requires Cupcake — no fallback

**Decision**: The Pi extension calls `cupcake eval --harness pi`. If Cupcake is not installed, the extension throws at session_start. No fallback to direct neph-cli.

**Rationale**: A fallback is a second code path that needs testing, maintenance, and failure handling. The whole point is one path.

### 6. neph-cli as Cupcake signal implementation

**Decision**: Cupcake's `neph_review` signal invokes `neph-cli review`. The signal passes normalized `{ path, content }` on stdin. neph-cli opens the review in Neovim via RPC, blocks until the user decides, and returns the decision on stdout. Cupcake's Rego policy reads the signal result and emits `allow`/`modify`/`deny`.

**Signal flow**:
```
Cupcake receives hook event
  → Deterministic policies evaluate (block rm -rf, protect .env, etc.)
  → If write/edit tool: neph_review signal fires
    → neph-cli review receives { path, content } on stdin
    → neph-cli connects to Neovim via $NVIM socket
    → review.open RPC opens vimdiff
    → User reviews hunks
    → neph-cli returns { decision, content } on stdout
  → Rego policy reads signal result
  → Emits allow / modify(updated_input) / deny
Cupcake returns decision to agent in agent-specific format
```

### 7. Hook configs point to Cupcake only

**Decision**:
- `.claude/settings.json`: `PreToolUse` → `cupcake eval --harness claude`
- `.gemini/settings.json`: `BeforeTool` → `cupcake eval --harness gemini`
- Pi extension: calls `cupcake eval --harness pi` internally

No hook ever points to `neph-cli` directly.

## Edge Cases

### Environment propagation (`$NVIM` through Cupcake signals)

**Problem**: When an agent runs inside Neovim's `:terminal`, `$NVIM` is set automatically. But Cupcake spawns signals as subprocesses — does `$NVIM` propagate?

**Expected**: Yes — standard OS behavior is for child processes to inherit the parent environment. Cupcake's docs don't mention environment sanitization.

**Required**: Must verify empirically. If `$NVIM` does NOT propagate, we need to either:
- Configure it explicitly in `rulebook.yml` signal config
- Pass it through the signal's stdin JSON
- Set `$NVIM_SOCKET_PATH` in the agent's launch environment

**Test**: Create a signal that echoes `$NVIM` to stderr. Run inside Neovim terminal. Verify it appears.

### Queued reviews vs signal timeout

**Problem**: Agent writes file A, then file B quickly. Both go through Cupcake. Both invoke `neph_review` signals. Signal A opens a review in Neovim. Signal B's review is queued by `review_queue.lua`. Both signals are burning their 600s timeout from the moment they were invoked.

If the user spends 8 minutes on review A, signal B has been running for 8 minutes when review B finally opens. If the user then spends 3+ minutes on review B, signal B hits 600s and Cupcake kills it.

**Mitigation**:
- Set signal timeout generously (600s covers most cases — 10 minutes)
- The review queue in Neovim shows queue position in the winbar ("Review 1/3") so the user knows more are waiting
- If a signal does timeout, the Rego policy defaults to `ask` (prompt user for manual approval)
- Future: neph-cli could reject queued reviews that have been waiting too long, so the timeout budget is spent on active review, not idle queuing

### Binary files

**Problem**: Agent writes an image, PDF, or other binary file. Passing binary content through stdin JSON is wasteful and review doesn't make sense.

**Mitigation**: The `neph_review` signal or neph-cli can detect non-text content (null bytes in content string) and auto-accept. Alternatively, a Rego policy can skip the signal for known binary extensions (`.png`, `.jpg`, `.pdf`, etc.).

### New files (file doesn't exist yet)

**Problem**: Agent creates a new file. Edit reconstruction fails because there's no file to read. Write review shows empty → new content.

**Handling**: This is fine. The review shows all content as "added" (all green in vimdiff). The user can accept or reject the entire file. No special handling needed.

### Agent dies mid-review

**Problem**: User is reviewing hunks in vimdiff. The agent process crashes. Since the hook blocks the agent, the agent dying kills the hook process, which kills Cupcake, which kills the signal, which kills neph-cli. But the review UI is still open in Neovim.

**Handling**: neph-cli's RPC connection to Neovim closes when neph-cli exits. The Lua side detects this via the existing `TabClosed`/`VimLeavePre` autocmds and the review queue's completion callback. The review UI becomes an orphan that the user can close manually. The user's partial decisions are lost (no one to receive them).

**Mitigation**: The existing `force_cleanup(agent_name)` in `review/init.lua` handles this — when the session detects the agent died, it finalizes the review with all undecided hunks rejected. The result goes nowhere (no caller), but the UI cleans up.

### Neovim exits mid-review

**Problem**: User closes Neovim while a review is open and neph-cli is blocking.

**Handling**: neph-cli's RPC call fails or the socket closes. neph-cli catches the error and exits. The signal exits. Cupcake gets a signal failure → Rego policy has no signal data → defaults to `ask` or `deny` based on policy configuration. The existing `VimLeavePre` autocmd in `review/init.lua` finalizes the review before Neovim exits.

### Multiple Neovim instances

**Problem**: User has two Neovim instances for two projects. Agent writes in project A. Which Neovim gets the review?

**Handling**: Existing `discoverNvimSocket()` in `transport.ts` handles this — matches by cwd, then by git root, then refuses to guess if ambiguous. When running inside Neovim's terminal, `$NVIM` points to the correct instance. When running outside, `$NVIM_SOCKET_PATH` must be set explicitly.

### Large files

**Problem**: Full file content passes through stdin → Cupcake → signal → neph-cli. Cupcake's Wasm runtime has a 10MB default memory limit.

**Handling**: The file content passes through the signal's stdin/stdout, not through the Wasm policy evaluator. Rego policies only see the signal *result* (`{ decision, content }`), not the full content during evaluation. The Wasm memory limit applies to policy logic, not signal I/O. Large files should work, but may hit Node.js stdin buffer limits (~1GB) or shell pipe limits. For truly massive files, this is an edge case we accept.

### Cupcake global vs project policies

**Handling**: Cupcake's two-phase evaluation runs global policies first (`~/.config/cupcake/`), then project policies (`.cupcake/`). Global policies cannot be overridden — if a global policy denies, project policies don't run. Document this so users understand that a team-wide `protected_paths` policy takes precedence.

## Risks / Trade-offs

**[Risk] Cupcake as hard dependency** — Every agent requires Cupcake installed.
→ Accepted: This is the design. One path. Cupcake has one-line installers. Document clearly.

**[Risk] Cupcake signal timeout** — If review takes longer than signal timeout, policy gets no data.
→ Mitigation: 600s timeout. Rego fallback = ask. Document queue implications.

**[Risk] Edit reconstruction in Cupcake signal** — For Edit tools, we need to read the current file and apply the diff before passing to neph-cli.
→ Mitigation: A `neph_reconstruct` signal or preprocessing step handles this. Simple, testable, isolated.

**[Risk] `$NVIM` propagation** — Untested whether Cupcake signals inherit the parent environment.
→ Mitigation: Test empirically. If it doesn't propagate, configure explicitly or pass via stdin.

**[Risk] Cupcake harness availability** — Cupcake doesn't have a Pi harness yet.
→ Mitigation: Build a thin Pi extension (~100 lines) that calls `cupcake eval`. When official support ships, migrate.

**[Risk] Double-hop latency** — Agent → Cupcake → neph-cli → Neovim adds hops.
→ Accepted: Policy eval is <1ms (Wasm). neph-cli startup is <100ms (Node). The review itself is human-speed. Latency is not a concern.

**[Trade-off] Cupcake becomes a SPOF** — If Cupcake has a bug, all agents are affected.
→ Accepted: One bug to fix vs. three separate bugs across three paths. This is simpler.

## Migration Plan

1. **Phase 1 — Simplify neph-cli review**: Strip per-agent normalizers and formatters. One protocol in, one protocol out. Tests.
2. **Phase 2 — Cupcake policies + signals**: Rego policies, rulebook with neph_review signal pointing to neph-cli. OPA tests.
3. **Phase 3 — Hook configs**: All agent hooks point to `cupcake eval`. E2E tests per agent.
4. **Phase 4 — Pi harness**: Rewrite Pi extension as Cupcake harness. Tests.
5. **Phase 5 — Dead code removal**: Delete bus, NephClient, gate, normalizers, Gemini sidecar.
6. **Phase 6 — Documentation + CI**: README, Cupcake setup guide, OPA in CI.

## Open Questions

- **Edit reconstruction**: Where exactly does it happen? In a separate Cupcake signal? In a Rego preprocessing step? In neph-cli after all (accepting `{ path, old_string, new_string }` as an alternative input)?
- **Cupcake signal data passing**: Can a signal pass structured JSON to the Rego policy, or only flat strings? Need to verify `input.signals.neph_review.content` works with full file contents.
- **Gemini CLI hook timeout**: Default 60s may be too short for interactive review. Can it be overridden?
- **`$NVIM` environment propagation**: Must verify empirically that Cupcake signals inherit the parent process environment.
