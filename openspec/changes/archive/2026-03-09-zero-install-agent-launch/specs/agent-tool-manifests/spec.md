## MODIFIED Requirements

### Requirement: Declarative tool manifest on AgentDef

`AgentDef` SHALL accept an optional `tools` field containing declarative install specifications. The `tools` table MAY contain `symlinks`, `merges`, `builds`, and `files` sub-fields. All paths in `src` fields SHALL be relative to the `tools/` directory inside the plugin root. `AgentDef` SHALL additionally accept an optional `launch_args_fn` field — a function `(root: string) -> string[]` — for agents that inject config at runtime instead of via persistent installation.

#### Scenario: Agent with launch_args_fn replaces merges

- **WHEN** an agent defines `launch_args_fn` to inject settings at runtime
- **THEN** the agent's `tools` field MAY omit the `merges` sub-field
- **AND** the runtime injection SHALL be the sole mechanism for that agent's hook integration

#### Scenario: Agent with both tools and launch_args_fn

- **WHEN** an agent defines both a `tools` field (e.g., for builds) AND a `launch_args_fn`
- **THEN** the `tools` field SHALL be processed by `tools.lua` for installation (builds, symlinks)
- **AND** `launch_args_fn` SHALL be called by `session.lua` at terminal open time
- **AND** neither mechanism SHALL interfere with the other

#### Scenario: Claude agent manifest after change

- **WHEN** the Claude agent definition is loaded
- **THEN** it SHALL NOT have a `tools.merges` field
- **AND** it SHALL have a `launch_args_fn` that returns `--settings` with inline hook JSON
- **AND** it MAY retain a `tools` field if it has builds or other install needs (currently it has none)
