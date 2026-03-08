## Context

After the composable DI architecture change, agents and backends are injected via `setup()`. But `tools.lua` still hardcodes agent-specific install knowledge in three static tables (`TOOLS`, `MERGE_TOOLS`, `builds`) plus a pi-specific `post_install` block. This is the last place where core "knows" about individual agents.

The test suite covers contracts, agent shapes, and config defaults, but doesn't test that real backends pass contract validation, that tool manifests are well-formed, or that the full setup wiring works end-to-end.

## Goals / Non-Goals

**Goals:**
- Move all agent-specific tool install specs onto `AgentDef.tools` — declarative manifests
- Make `tools.lua` a generic manifest executor with zero agent names
- Validate tool manifests at setup time via contracts
- Add backend conformance, tool manifest, setup smoke, and negative path tests

**Non-Goals:**
- Changing the actual install behavior (symlinks, merges, builds still work the same way)
- Moving the `tools/` directory structure (files on disk stay where they are)
- Adding new install capabilities beyond what exists today
- Testing actual filesystem side effects (symlink creation, npm builds)

## Decisions

### 1. Declarative tool manifest on AgentDef

**Decision**: Add optional `tools` field to `AgentDef` with four sub-fields: `symlinks`, `merges`, `builds`, `files`.

**Rationale**: Each agent knows its own filesystem layout. The manifest is pure data — no functions, no escape hatches. The core executor doesn't need to know what "pi" or "claude" means.

```lua
tools = {
  symlinks = {
    { src = "pi/package.json", dst = "~/.pi/agent/extensions/nvim/package.json" },
  },
  merges = {
    { src = "claude/settings.json", dst = "~/.claude/settings.json", key = "hooks" },
  },
  builds = {
    { dir = "pi", src_dirs = { ".", "../lib" }, check = "dist/pi.js" },
  },
  files = {
    { dst = "~/.pi/agent/extensions/nvim/index.ts",
      content = 'export { default } from "./dist/pi.js";',
      mode = "create_only" },
  },
}
```

**Alternative considered**: `post_install` function on the agent for pi's index.ts creation. Rejected because a function is an escape hatch that breaks the declarative contract. The `files` verb with `mode = "create_only"` covers the use case without functions in data.

### 2. `files` verb with modes

**Decision**: The `files` spec supports `mode = "create_only"` (write only if file doesn't exist) and `mode = "overwrite"` (always write). Default is `create_only`.

**Rationale**: Pi's index.ts wrapper needs to be created once but not overwritten if the user modified it. Other future use cases might need overwrite. Two modes covers both without complexity.

### 3. Tool manifest validation in contracts.lua

**Decision**: Add `validate_tools(agent)` that checks the shape of `agent.tools` if present. Called during setup for each agent.

**Rationale**: Catches manifest typos at startup (e.g., `symlink` instead of `symlinks`, missing `src` field) rather than silent install failures.

### 4. neph-cli stays in tools.lua as the sole universal tool

**Decision**: The neph-cli build/symlink spec remains in `tools.lua` since it's agent-independent (universal infrastructure).

**Rationale**: neph-cli is not associated with any agent — it's the plugin's own CLI. It doesn't belong on any AgentDef.

### 5. Test strategy: contract conformance + wiring smoke + negative paths

**Decision**: Four new test categories:
1. Backend conformance: actual `neph.backends.snacks` and `neph.backends.wezterm` pass `validate_backend()`
2. Tool manifest validation: valid/invalid manifests, edge cases
3. Setup smoke test: full `setup()` with real agent submodules + stub backend wires correctly
4. Negative paths: missing backend, invalid agent, malformed manifest through `setup()`

**Rationale**: Tests the integration seams — where modules hand off to each other. Individual module tests already exist; these test the glue.

## Risks / Trade-offs

**[Manifest verbosity]** → Agent submodules with tools get longer (pi.lua goes from ~20 lines to ~40). Mitigation: the manifest is self-documenting data. One place to look for everything about an agent.

**[Build specs tied to plugin root]** → `builds[].dir` is relative to `tools/` in the plugin root. This couples agent manifests to the repo layout. Mitigation: this coupling already exists in `tools.lua` today — we're just moving it, not adding it.

**[create_only mode subtlety]** → If a user deletes the pi index.ts, it gets recreated on next startup. This is the current behavior, just made explicit via `mode = "create_only"`.
