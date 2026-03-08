## Why

The codebase underwent two major architectural changes — composable DI (constructor injection for agents/backends) and agent-owned tooling (declarative tool manifests on AgentDef) — but the documentation was never updated. AGENTS.md still references deleted directories (`internal/backends/`), removed config fields (`multiplexer`, `enabled_agents`), and obsolete patterns (hardcoded agent lists, string-enum backend selection). `docs/testing.md` doesn't mention the 7 new test suites added during the restructure. New contributors and AI agents working in the codebase will follow incorrect guidance.

## What Changes

- **Rewrite AGENTS.md** to reflect constructor injection, agent submodules (`lua/neph/agents/*.lua`), backend modules (`lua/neph/backends/*.lua`), contract validation, and declarative tool manifests
- **Update code organization tree** in AGENTS.md — remove deleted paths, add new paths (`agents/`, `backends/`, `contracts.lua`)
- **Rewrite "Adding a New Agent" section** — now requires creating a submodule file, not editing a table
- **Rewrite "Multiplexer Backends" section** — now "Backend Modules" with DI pattern, remove tmux/zellij stubs
- **Update installation example** — show new `agents = { ... }, backend = ...` setup pattern
- **Update `docs/testing.md`** — document all test suites: contracts, agent submodules, backend conformance, setup smoke, placeholders, config, session, tools manifest validation
- **Update gotchas** — remove stale references to `internal/backends/`, `multiplexer`, `full_cmd` runtime computation
- **Verify `docs/rpc-protocol.md`** against current `protocol.json` — ensure method list is accurate
- **Update module-level EmmyLua docstrings** in key files where the brief description references old architecture

## Capabilities

### New Capabilities

- `docs-accuracy`: Ensures all documentation files (AGENTS.md, docs/*.md) accurately reflect the current constructor-injection architecture, agent submodule pattern, backend module pattern, and test coverage

### Modified Capabilities

<!-- No existing specs have requirement-level changes — this is purely a documentation update -->

## Impact

- **AGENTS.md** — full rewrite of sections 4 (Agent Registration), Multiplexer Backends, Code Organization, Adding a New Agent, Adding a New Backend, Installation, and several gotchas
- **docs/testing.md** — expand to cover all 9+ test files
- **docs/rpc-protocol.md** — minor verification pass
- **Lua module docstrings** — targeted updates to files whose `@brief` or `@mod` annotations reference old patterns
- **No code changes** — this is documentation only
