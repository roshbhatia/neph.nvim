## Context

Neph currently mixes integration concerns (agent hooks, policy enforcement, Neovim review UX, installation) across multiple paths. Cupcake is powerful but only supports specific harnesses, leaving gaps for agents like Amp, Gemini, Pi, and terminal-first agents. Neovim also owns install flows (`:NephTools`) that need to shift into the CLI. We need a composable integration model that works across varying hook capabilities while keeping policy enforcement and review UX swappable.

## Goals / Non-Goals

**Goals:**
- Define a canonical integration pipeline with explicit, pluggable stages.
- Support group defaults (dependency trees) with per-agent overrides.
- Treat the policy engine as a mandatory stage (with `noop` option).
- Make the Neovim diff-hunk review provider explicitly opt-in with a `noop` default.
- Move integration install/status/validation to the neph CLI.
- Preserve compatibility with Cupcake when available while supporting non-harness agents.

**Non-Goals:**
- Implement new Cupcake harnesses for unsupported agents.
- Replace existing review engine/UI behavior in Neovim.
- Build a new policy engine; this change focuses on composability and integration contracts.

## Decisions

### 1) Canonical Integration Pipeline
**Decision:** Standardize a pipeline: Adapter → Policy Engine → Review Provider → Response Formatter.

**Why:** Each step has distinct responsibilities and needs to remain independently replaceable.

**Alternatives considered:**
- Monolithic integration per agent: rejected (non-composable, duplicated logic).
- Policy-only without review provider: rejected (removes the Neovim review UX).

**Diagram:**
```
Agent Event
  └─ Adapter (agent-specific)
       └─ Canonical Event
            └─ Policy Engine (cupcake|noop|alt)
                 └─ Review Provider (vimdiff|ask|noop)
                      └─ Canonical Decision
                           └─ Response Formatter (agent-specific)
```

### 2) Group Defaults with Dependency Trees
**Decision:** Use group defaults to define dependency trees (policy engine, review provider, formatter), with per-agent overrides.

**Why:** Agents share integration patterns (e.g., harness-backed vs hook-based). Group defaults keep config compact while allowing exceptions.

**Alternatives considered:**
- Per-agent explicit config only: rejected (verbose, hard to maintain).

### 3) Policy Engine is Mandatory (Composable)
**Decision:** Every integration pipeline includes a policy engine stage, defaulting to `noop` when no enforcement is desired.

**Why:** Makes enforcement consistent and explicit even when disabled; avoids hidden bypasses.

**Alternatives considered:**
- Optional policy engine: rejected (hard to reason about dependencies).

### 4) Review Provider Opt-In with Noop Default
**Decision:** Review provider must be explicitly registered. Default is `noop` to preserve normal write behavior when not configured.

**Why:** Mirrors how agents/backends are injected and avoids implicit coupling to Neovim UX.

**Alternatives considered:**
- Global review enable flag: rejected (too implicit, less composable).

### 5) CLI-Managed Integration
**Decision:** Integration install/validation/status moves to `neph` CLI (`neph integration`, `neph deps`). Neovim `:NephTools` is deprecated.

**Why:** Integration should be editor-agnostic, and CLI is the natural place for dependency checks and config manipulation.

**Alternatives considered:**
- Keep Neovim installer: rejected (ties integration to Neovim startup and limits portability).

### 6) Canonical Decision Envelope
**Decision:** Standardize a decision envelope (`allow|deny|ask|modify` plus optional `updated_input` and `reason`) across all pipeline stages.

**Why:** Enables policy engines and review providers to compose without agent-specific formats.

**Alternatives considered:**
- Agent-native decisions everywhere: rejected (no shared contract).

## Risks / Trade-offs

- **[Risk] CLI dependency for integration management** → Mitigation: keep review provider `noop` by default; clear `neph deps status` output for missing dependencies.
- **[Risk] Ask/modify support varies by agent** → Mitigation: response formatter maps unsupported decisions (e.g., ask→deny) with explicit messaging.
- **[Risk] Increased configuration surface** → Mitigation: group defaults + sane presets minimize required config.
- **[Risk] Loss of `:NephTools` flow** → Mitigation: CLI provides equivalent commands and `:checkhealth` surfaces CLI status.

## Migration Plan

1. Introduce integration pipeline interfaces and canonical event/decision shapes.
2. Add group defaults and per-agent override wiring in config.
3. Implement `neph integration` and `neph deps` CLI commands.
4. Update Neovim health reporting to read CLI status.
5. Deprecate `:NephTools` and update documentation/tests.

## Open Questions

- Which default group assignments should be shipped for Amp/Gemini/Pi/Codex/Crush/Goose?
- Should the policy engine expose additional signals beyond review (e.g., lint/test)?
- Should the CLI offer a machine-readable JSON status schema for IDE integrations?
