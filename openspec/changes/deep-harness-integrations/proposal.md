# Deep Harness Integrations

## Problem

neph.nvim's current hook-based integrations (Claude, Copilot, Cursor, Gemini) invoke Cupcake
via a raw shell command (`cupcake eval --harness <agent>`). This model is limited — not because
Cupcake is wrong, but because the glue layer is too thin:

- **No partial accept**: The current shell-invocation model can't return `updatedInput` to the
  agent. Cupcake already supports `modify` decisions with `updated_input` — we're just not
  threading it through.
- **No session lifecycle signals**: Claude/Copilot/Cursor/Gemini have SessionStart/SessionEnd/Stop
  hooks that are unwired. Neovim has no visibility into whether an agent is active, running,
  or idle.
- **No post-write checktime**: Only Pi and Amp trigger buffer refresh after agent writes.
- **Cursor is post-write by design**: `afterFileEdit` fires after the file is already on disk.
  There is **no pre-write file hook in Cursor** (confirmed; community feature request was not
  implemented). Permanent limitation.
- **Exit-code hacks**: Using exit code 2 to signal deny is fragile. Claude/Gemini/Codex all
  support structured JSON output (`hookSpecificOutput`) — the native protocol.
- **Gemini and Amp bypass Cupcake entirely**: `tools/gemini/settings.json` calls
  `neph integration hook gemini` which goes straight to neph review. `neph-plugin.ts` calls
  `review()` directly. Both skip the policy layer — no protected_paths check, no
  dangerous_commands block.

The design principle: **most deterministic, native-feeling integration.** TypeScript harnesses
over exit-code hacks. Structured JSON output over exit codes. Pre-write over post-write. But
critically: **Cupcake stays in the pipeline** — it's not a workaround to replace but a genuine
policy layer to preserve and generalize.

## Research Findings (all 5 subagents complete)

### Q1: Cursor `beforeFileEdit` — does it exist?

**No, and it won't.** Cursor v1.7+ has exactly 6 hooks: `beforeSubmitPrompt`,
`beforeShellExecution`, `beforeMCPExecution`, `beforeReadFile`, `afterFileEdit`, `stop`.
A pre-write file hook was requested by the community; it was not implemented. **Cursor file
write review is permanently post-write.** Correct integration points:
- `beforeShellExecution` — gate shell commands (pre-execution, can block) ← not currently used
- `beforeMCPExecution` — gate MCP tool calls (pre-execution, can block) ← not currently used
- `afterFileEdit` — post-write buffer refresh only (cannot reject) ← current, keep

### Q2: Claude `PermissionRequest` vs `PreToolUse`

**Use `PreToolUse`. `PermissionRequest` is a trap.**

`PermissionRequest` has known unfixed bugs: deny behavior is silently ignored
(anthropics/claude-code#19298), it doesn't fire in VS Code/Desktop, and it doesn't fire in
`acceptEdits` mode (the most common code review workflow). `PreToolUse` fires on every
Edit/Write regardless of mode and works across all surfaces.

**The exit-code hack should be replaced with structured JSON.** Claude's hook system accepts
`hookSpecificOutput` with `permissionDecision: "allow"|"deny"|"ask"` and `updatedInput` for
partial accept. This is the documented native protocol — cleaner, not dependent on exit codes.

Known caveats: `updatedInput` in Claude's `PreToolUse` has an open bug where it may be
silently ignored (anthropics/claude-code#26506). Claude can also bypass `Edit` hooks via Bash
(#29709). These are open upstream bugs. The structured JSON approach is still the right
direction even with these caveats.

### Q3: Amp `tool.call` — does it support input modification?

**Yes, the API has stabilized and supports `modify`:**

```typescript
type ToolCallResult =
  | { action: 'allow' }
  | { action: 'reject-and-continue'; message: string }
  | { action: 'modify'; input: Record<string, unknown> }  // ← partial accept
  | { action: 'synthesize'; result: { output: string; exitCode?: number } }
  | { action: 'error'; message: string }
```

Partial accept in neph-plugin.ts requires returning `{ action: 'modify', input: {...} }` with
the user-edited content. The API has full type definitions in the official Amp manual.

### Q4: Cupcake — what does it uniquely provide?

**Critical finding: Cupcake is a genuine policy layer, not just a review gateway. Do not bypass it.**

Cupcake runs OPA/Rego policies (compiled to Wasm) **before** invoking neph review:
- `protected_paths.rego` — blocks writes to `.env`, `id_rsa`, credentials files **before
  review is offered**
- `dangerous_commands.rego` — blocks `rm -rf`, `git push -f`, `--no-verify` **without
  user interaction**
- `review.rego` — routes write/edit tools to neph review; other tools skip it entirely

A TypeScript harness calling neph review directly **loses all of this**. Gemini and Amp already
have this gap — dangerous command blocking and protected path enforcement are absent for those
agents today. Pi is the correct model: TypeScript harness → Cupcake eval → neph review.

Cupcake also provides: extensible project-local Rego rules (`.cupcake/policies/`), pluggable
signal system for audit logging and notifications (`.cupcake/signals/`), `modify` decisions
with `updated_input` (partial accept already supported at the policy level), and structured
audit trail with `rule_id`/`severity` per decision.

**Architecture clarification:**
- Cupcake = fast, declarative, extensible **pre-filter** (policy enforcement)
- neph review = interactive, human-driven **review UI** (for what Cupcake lets through)

They solve different problems. The TypeScript harness wraps Cupcake; it does not replace it.

### Q5: Shared `lib/harness-base.ts` feasibility

**Yes, worth building for 3+ harnesses.**

Break-even at ~3.4 harnesses. With Claude + Gemini + Codex + Copilot planned (6 total), ROI
is strong. Extract:
- `ContentHelper` — content reconstruction from old_string/new_string diffs
- `ReviewHelper` — `reviewWrite()` wrapping neph-run.ts with normalized decision types
- `SessionHelper` — active/running/idle state signals; two backends (persistent queue for
  low-overhead persistent processes vs execFileSync for simplicity)
- Shared `WriteEvent` / `WriteDecision` types

The base cannot abstract hook registration (each platform's event model differs), tool
definition, decision application, or UI wiring — those stay per-harness. Phased approach:
ContentHelper + ReviewHelper first, validated against Amp and Pi.

## Revised Architecture

The correct model (Pi is the reference implementation):

```
TypeScript harness
  ├── Hook registration (platform-specific: amp.on(), pi.registerTool(), settings.json cmd, ...)
  ├── Session lifecycle signals (SessionStart/End, agent start/stop → neph-cli set/unset)
  ├── Content reconstruction (via lib/harness-base.ts ContentHelper)
  └── cupcake eval --harness <agent>
        ├── protected_paths.rego   → block before review
        ├── dangerous_commands.rego → block before review
        └── review.rego → neph_review signal
              └── neph-cli review → interactive vimdiff
                    └── decision + updatedInput → back up the stack
```

Gemini and Amp need to be **pulled back into this pipeline** — they currently bypass the
policy layer. New harnesses (Claude, Codex, Copilot) should go through Cupcake from the start.

## Proposed Changes

### 1. `lib/harness-base.ts` — shared infrastructure

Extract from Amp and Pi: ContentHelper, ReviewHelper, SessionHelper, shared types.
Build and validate before writing new harnesses.

### 2. Amp — add Cupcake policy layer + partial accept

`neph-plugin.ts` currently calls neph review directly, bypassing Cupcake. Fix:
- Route through `cupcake eval --harness amp` for policy enforcement
- Add `{ action: 'modify', input: {...} }` return for partial accept
- Refactor using `lib/harness-base.ts`

### 3. Gemini — add Cupcake policy layer

`neph integration hook gemini` calls review directly. Fix:
- Route through `cupcake eval --harness gemini`
- `tools/gemini/settings.json` already uses `neph integration hook gemini` — update the
  implementation behind it
- Consider: add session lifecycle hooks (`BeforeAgent`/`AfterAgent`/`SessionStart`/`SessionEnd`)
  via a TypeScript harness instead of a static settings.json

### 4. Claude — TypeScript harness (replaces static settings.json hook command)

`tools/claude/settings.json` currently: `"command": "cupcake eval --harness claude"`

Replace with a TypeScript harness binary (`tools/claude/harness.ts`) that:
- Reads tool event from stdin
- Handles `SessionStart`/`SessionEnd`/`Stop` hooks for lifecycle signals
- Routes `PreToolUse` (Edit/Write) through `cupcake eval --harness claude`
- Emits structured `hookSpecificOutput` JSON (not exit codes)
- Threads `updated_input` from Cupcake's `modify` decision back as `updatedInput`
- Fires checktime via neph-cli on `PostToolUse` write completions

### 5. Codex — TypeScript harness (new, currently unwired)

Write `tools/codex/harness.ts` following the Claude harness model. Register in Codex hooks
config. Codex supports `PreToolUse` and full `updatedInput` — same pattern.

### 6. Copilot — TypeScript harness (replaces static hooks.json command)

`tools/copilot/hooks.json` currently: `"command": "cupcake eval --harness copilot"`

Replace with a TypeScript harness for lifecycle signals and structured JSON output.
Note: Copilot's `preToolUse` API only supports `allow/deny/ask` — no `updatedInput`. Partial
accept not possible for Copilot.

### 7. Cursor — correct the integration

- Remove the implicit "review" intent from `afterFileEdit` — it was never actually pre-write
- Keep `afterFileEdit` for checktime-only (buffer refresh after Cursor writes)
- Add `beforeShellExecution` hook for shell command gating through Cupcake
- Add `beforeMCPExecution` hook for MCP tool gating through Cupcake
- Document the file write limitation explicitly

### 8. OpenCode — add session lifecycle

OpenCode's SSE integration is already at max depth for pre-write interception. Gap: no session
lifecycle signals. Add `SessionStart`/`SessionEnd` handling to subscribe/unsubscribe SSE and
signal Neovim active state.

## Integration Depth Matrix (post-implementation)

```
                   PRE-WRITE   POLICY      SESSION      PARTIAL    POST-WRITE
                   INTERCEPT   LAYER       LIFECYCLE    ACCEPT     REFRESH
                 ─────────────────────────────────────────────────────────────
Pi               ✓ custom      ✓ Cupcake   ✓ full       ✓          ✓
Amp              ✓ tool.call   ✓ (new)     ✓ full       ✓ (new)    ✓
─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
Claude           ✓ PreToolUse  ✓ Cupcake   ✓ (new)      ✓ (new)*   ✓ (new)
Gemini           ✓ BeforeTool  ✓ (new)     ✓ (new)      ✓ (new)    ✓ AfterTool
Codex            ✓ (new)       ✓ (new)     ✓ (new)      ✓ (new)    ✓ (new)
Copilot          ✓ preToolUse  ✓ Cupcake   ✓ (new)      ✗ API      ✓ (new)
OpenCode         ✓ SSE perm    n/a native  ✓ (new)      ✗          ✓ file.edit
─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
Cursor           ✗ permanent   ✓ shell/MCP  ✗ no hooks  ✗          ✓ checktime
Goose            ✗ deferred
Crush            ✗ deferred
```
`*` Claude `updatedInput` has an open upstream bug; behavior may vary by version.

## Non-Goals

- Goose and Crush deep integration (no native hook system; MCP wrapper path deferred)
- Removing Cupcake — it is the policy layer and must remain in the pipeline
- Changing the neph review protocol or Lua-side architecture
- Read tracking for hook-based agents (Pi-specific; not worth generalizing yet)

## Success Criteria

- All agents route file write decisions through Cupcake (policy enforcement restored for Amp/Gemini)
- Claude, Gemini, Codex, Copilot: TypeScript harnesses — structured JSON output, no exit-code hacks
- Claude, Gemini, Codex: partial accept via `updatedInput` threaded from Cupcake `modify` decision
- All Tier 1 agents: session lifecycle signals visible in Neovim statusline
- All Tier 1 agents: post-write checktime triggers buffer refresh
- Amp: partial accept via `{ action: 'modify' }` 
- Cursor: corrected to checktime + shell/MCP gating; file write limitation documented
- `lib/harness-base.ts` extracted and shared across Amp, Pi, and new harnesses
- Cupcake policy coverage consistent across all agents (same `.cupcake/policies/` applies)

---

_Last updated: 2026-04-05 — all 5 subagent research questions resolved_
