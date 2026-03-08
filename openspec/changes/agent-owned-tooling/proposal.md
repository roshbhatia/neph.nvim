## Why

`tools.lua` hardcodes agent-specific install manifests (symlinks, JSON merges, builds, post-install hooks) for pi, claude, cursor, amp, opencode, and gemini. This means the core knows about every agent's filesystem layout — adding a new agent's tooling requires editing `tools.lua`. With the composable DI architecture now in place, tool install specs should live on the agent definitions themselves, and the core should be a generic executor that processes whatever manifests are injected.

Additionally, the integration layers between agents, backends, contracts, and tools lack adequate test coverage. Backend contract conformance, tool manifest validation, and full setup wiring are untested.

## What Changes

- Add optional `tools` field to `AgentDef` — a declarative manifest with `symlinks`, `merges`, `builds`, and `files` sub-fields
- Move all agent-specific install specs from `tools.lua` TOOLS/MERGE_TOOLS/builds constants into each agent's submodule (`neph.agents.pi`, `neph.agents.claude`, etc.)
- Rewrite `tools.lua` to iterate injected agents and process their `tools` manifests generically — zero agent names in core
- Add `validate_tools(agent)` to `contracts.lua` for tool manifest shape validation at setup time
- Add backend contract conformance tests (actual snacks/wezterm modules pass validation)
- Add tool manifest contract tests
- Add full setup wiring smoke test
- Add negative path tests for setup() error handling

## Capabilities

### New Capabilities
- `agent-tool-manifests`: Declarative tool install manifests on AgentDef — symlinks, merges, builds, files
- `integration-test-coverage`: Backend conformance, tool manifest validation, setup wiring smoke tests, negative paths

### Modified Capabilities
- `agent-submodules`: AgentDef gains optional `tools` field with install manifest
- `constructor-injection`: `validate_agent()` extended to validate `tools` sub-fields; `validate_tools()` added
- `tool-install`: `tools.lua` becomes agent-agnostic — reads manifests from injected agents, no hardcoded TOOLS/MERGE_TOOLS/builds lists
- `selective-install`: Selection now implicit — only injected agents' tool manifests are processed

## Impact

- **Agent submodules**: `lua/neph/agents/pi.lua`, `claude.lua`, `cursor.lua`, `amp.lua`, `opencode.lua`, `gemini.lua` gain `tools` fields
- **Core tools.lua**: Rewritten to be fully generic — iterates agent manifests
- **Contracts**: `validate_tools()` added, `validate_agent()` extended
- **Tests**: New test files for backend conformance, tool manifests, setup smoke, negative paths
- **No API changes**: `require("neph.api")` unchanged
- **No config changes**: `neph.Config` unchanged
