## MODIFIED Requirements

### Requirement: AgentDef supports dynamic launch args

`AgentDef` SHALL accept an optional `launch_args_fn` field — a function that takes the plugin root path (string) and returns a list of additional CLI arguments (string[]). `AgentDef` SHALL additionally accept an optional `ready_pattern` field — a Lua string pattern matched against terminal output to detect when the agent is ready to accept input. When present, `session.lua:open()` SHALL call `launch_args_fn(plugin_root)` and append the returned arguments to the agent's static `args` before constructing the full command.

#### Scenario: Agent with launch_args_fn

- **WHEN** an agent defines `launch_args_fn = function(root) return {"--settings", '{"key":"val"}'} end`
- **AND** the agent's static `args` is `{"--permission-mode", "plan"}`
- **THEN** the resolved args at launch time SHALL be `{"--permission-mode", "plan", "--settings", '{"key":"val"}'}`

#### Scenario: Agent without launch_args_fn

- **WHEN** an agent does not define a `launch_args_fn` field
- **THEN** `session.lua:open()` SHALL use the static `args` unchanged
- **AND** no error SHALL occur

#### Scenario: Agent with ready_pattern

- **WHEN** an agent defines `ready_pattern = "^%s*>"`
- **THEN** contract validation SHALL accept the field as a valid optional string
- **AND** the pattern SHALL be available to backends for ready detection
