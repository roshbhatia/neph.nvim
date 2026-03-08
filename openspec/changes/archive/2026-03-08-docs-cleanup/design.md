## Context

AGENTS.md and docs/*.md were written for the original architecture which used:
- Hardcoded agent list in `internal/agents.lua` with a `merge()` function for user overrides
- String-enum `multiplexer` config field selecting between `snacks`/`wezterm`/`tmux`/`zellij`
- Backend adapters in `internal/backends/` directory
- Tool installation hardcoded per-agent in `tools.lua`

Two changes landed (composable-di-architecture, agent-owned-tooling) that replaced all of this with:
- Constructor injection: agents and backend passed as values into `setup()`
- Agent submodules at `lua/neph/agents/*.lua` returning pure `AgentDef` tables
- Backend modules at `lua/neph/backends/*.lua` conforming to a validated interface
- Contract validation via `internal/contracts.lua` (validate_agent, validate_backend, validate_tools)
- Declarative tool manifests on `AgentDef.tools` with four verbs: symlinks, merges, builds, files

The documentation now actively misleads anyone reading it.

## Goals / Non-Goals

**Goals:**
- Every doc file accurately reflects the current constructor-injection architecture
- Code organization trees match the actual filesystem
- "How to add X" guides show the correct patterns
- Testing docs cover all test suites (currently 9+ spec files, ~160 tests)
- Module-level EmmyLua docstrings don't reference removed concepts

**Non-Goals:**
- Adding new documentation topics not already covered
- Rewriting the README (out of scope — this is internal/dev docs)
- Changing any code behavior
- Updating openspec archived change docs (they're historical records)

## Decisions

1. **Section-by-section rewrite of AGENTS.md rather than full replacement**: The structure of AGENTS.md (overview → commands → code org → patterns → testing → gotchas → adding features) is sound. We rewrite content within existing sections rather than restructuring. This preserves familiarity for contributors who've read it before.

2. **Expand docs/testing.md to list all test files**: Currently it only mentions review engine and contract tests. We add entries for: contracts_spec, agent_submodules_spec, backend_conformance_spec, setup_smoke_spec, agents_spec, config_spec, session_spec, placeholders_spec, plus the existing ones.

3. **Minimal changes to docs/rpc-protocol.md**: After verification against protocol.json, only update if methods are missing or incorrect. This doc was not affected by the DI restructure.

4. **Targeted EmmyLua updates**: Only update `@mod` and `@brief` annotations in files where they reference removed concepts (e.g., `multiplexer`, `internal/backends/`). Don't touch annotations that are still accurate.

## Risks / Trade-offs

- **Stale context in openspec schema**: The openspec `context` field still references the old repo structure (it shows `internal/backends/`, `multiplexer`, etc.). This is an openspec config issue, not a docs issue — out of scope but worth noting.
- **Docs drift again**: No automated check ensures docs stay in sync with code. Mitigation: the contract tests and agent submodule tests act as a canary — if the architecture changes, tests break before docs can drift silently.
