## Context

neph.nvim currently hardcodes 10 agent definitions in `lua/neph/internal/agents.lua` and resolves backends via an if/elseif chain in `session.lua`. The `enabled_agents` string allowlist and `multiplexer` string enum exist as workarounds for the fact that core owns all definitions. Users cannot add agents without editing plugin source, and every new agent requires a PR to the agent list.

The current backend interface (`setup`, `open`, `focus`, `hide`, `show`, `is_visible`, `kill`, `cleanup_all`) is already well-defined but enforced only by convention — nothing validates that a backend module actually implements the contract.

## Goals / Non-Goals

**Goals:**
- Constructor injection: agents and backend passed directly into `setup()` as Lua values
- Contract validation at setup time — fail loud with clear errors, not at runtime
- Agent definitions as standalone submodules under `neph.agents.*`
- Backend implementations as standalone submodules under `neph.backends.*`
- Remove `enabled_agents`, `multiplexer` config keys, and `agents.merge()`
- `neph.internal.agents` becomes a thin accessor over the injected array (no hardcoded list)

**Non-Goals:**
- Separate GitHub repos for agents/backends (same repo, separate Lua modules)
- Runtime hot-swapping of backends or agents after `setup()`
- Auto-detection of any kind — everything is explicit
- Backward compatibility shims for old `multiplexer`/`enabled_agents` config keys

## Decisions

### 1. Constructor injection over registry pattern

**Decision**: Users pass agent tables and a backend module directly into `setup()`. No registry module.

**Rationale**: A registry adds indirection (register + lookup) when we can just pass values. The user already has the reference at config time via `require()`. A registry would only add value for late registration or introspection — neither of which we need.

**Alternative considered**: `neph.registry` module with `register("agents", name, def)` / `get("agents", name)`. Rejected because it creates coupling between submodules and core (submodules need to know about the registry), and adds a load-order dependency.

```lua
-- Chosen pattern:
require("neph").setup({
  agents = {
    require("neph.agents.claude"),
    require("neph.agents.goose"),
  },
  backend = require("neph.backends.snacks"),
})
```

### 2. Agent submodules return pure data tables

**Decision**: Each `neph.agents.<name>` module returns an `AgentDef` table. No side effects on require.

**Rationale**: Pure data is testable, composable, and has no load-order constraints. Users can inspect, filter, or transform agent defs before passing them to `setup()`.

```lua
-- lua/neph/agents/claude.lua
return {
  name = "claude",
  label = "Claude",
  icon = "  ",
  cmd = "claude",
  args = { "--permission-mode", "plan" },
  integration = { type = "hook", capabilities = { "review", "status", "checktime" } },
}
```

### 3. Backend submodules return module tables with methods

**Decision**: Each `neph.backends.<name>` module returns a table conforming to the backend interface. Validated at setup time.

**Rationale**: Backends have behavior (methods), not just data. They must conform to a fixed interface. Validation at setup time catches missing methods immediately.

### 4. Contract validation via `contracts.lua`

**Decision**: New `lua/neph/internal/contracts.lua` module with `validate_agent(def)` and `validate_backend(mod)` functions. Called during `setup()`. Throws on invalid input.

**Rationale**: Fail loud at setup time with clear error messages. "backend 'foo' missing required method 'is_visible'" is infinitely better than a nil index error when someone tries to open a terminal 10 minutes later.

**Required agent fields**: `name` (string), `cmd` (string), `label` (string), `icon` (string)
**Optional agent fields**: `args` (string[]), `integration` (table), `send_adapter` (function)
**Required backend methods**: `setup`, `open`, `focus`, `hide`, `is_visible`, `kill`, `cleanup_all`

### 5. Directory layout: `neph.agents.*` and `neph.backends.*`

**Decision**: Agent and backend submodules live at `lua/neph/agents/` and `lua/neph/backends/` respectively — peer directories to `internal/` and `api/`.

**Rationale**: They're part of the neph package namespace but are user-facing modules (users `require()` them). Placing them under `internal/` would be misleading. Placing them outside `neph/` would break the package namespace.

```
lua/neph/
├── agents/           ← user-facing, require("neph.agents.claude")
│   ├── claude.lua
│   ├── ...
│   └── all.lua
├── backends/         ← user-facing, require("neph.backends.snacks")
│   ├── snacks.lua
│   └── wezterm.lua
├── internal/         ← private implementation
├── api/              ← public API
├── init.lua
└── config.lua
```

### 6. `all.lua` convenience module

**Decision**: Provide `neph.agents.all` that returns an array of all available agent defs. Available but not promoted.

**Rationale**: Useful for discovery and for users who want everything. But the default examples in docs should show explicit selection.

### 7. `agents.lua` internal module becomes a thin accessor

**Decision**: `neph.internal.agents` keeps `get_all()` and `get_by_name()` but loses its hardcoded list and `merge()`. It receives the agent array from `setup()` and filters by executable availability.

**Rationale**: Other internal modules (picker, terminal, session) already depend on `agents.get_all()` and `agents.get_by_name()`. Keeping this accessor layer avoids threading the agent array through every call site. The module just switches from owning the data to receiving it.

### 8. Remove tmux/zellij stub backends

**Decision**: Delete `lua/neph/internal/backends/tmux.lua` and `zellij.lua`. They were stubs that warned and fell back to snacks. With explicit injection, there's nothing to stub — if a user doesn't inject a backend, they get an error.

**Alternative considered**: Move stubs to `neph.backends.tmux` and `neph.backends.zellij`. Rejected — stubs that do nothing but warn add noise. They can be added as real implementations later.

## Risks / Trade-offs

**[Breaking change]** → Existing configs using `multiplexer` or `enabled_agents` will error. Mitigation: Clear error messages at setup time explaining the migration. This is a deliberate break, not accidental.

**[No default agents]** → Users who call `setup({})` with no agents get zero agents. Mitigation: `validate_config()` warns if agents array is empty. Documentation shows the recommended setup with explicit agents.

**[No default backend]** → Users who call `setup({})` with no backend get an error. Mitigation: Error message says "no backend registered — pass backend = require('neph.backends.snacks')". Could alternatively default to snacks, but that contradicts the "explicit everything" philosophy. We'll require it.

**[More verbose setup]** → User config goes from 1 line (`opts = {}`) to ~8 lines. Mitigation: This is the intended trade-off. Explicit is better than implicit. The `all.lua` module exists for the concise path.
