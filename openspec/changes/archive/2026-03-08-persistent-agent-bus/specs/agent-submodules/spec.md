## MODIFIED Requirements

### Requirement: Agent definition submodules
neph.nvim SHALL provide standalone Lua modules under `lua/neph/agents/` where each module returns a single `AgentDef` table. Modules SHALL have no side effects on require. Agents that require tool installation SHALL include a `tools` field with a declarative install manifest. Extension and hook agents SHALL declare their type via a `type` field.

#### Scenario: Require pi agent
- **WHEN** `require("neph.agents.pi")` is called
- **THEN** it SHALL return a table with `name = "pi"`, `type = "extension"`, and a `tools` field
- **AND** the table SHALL NOT have a `send_adapter` field
- **AND** the table SHALL NOT have an `integration` field

#### Scenario: Require claude agent
- **WHEN** `require("neph.agents.claude")` is called
- **THEN** it SHALL return a table with `name = "claude"`, `type = "hook"`, and a `tools` field
- **AND** the table SHALL NOT have an `integration` field

#### Scenario: Require goose agent (terminal, no type)
- **WHEN** `require("neph.agents.goose")` is called
- **THEN** it SHALL return a table with `name = "goose"` and no `type` field

#### Scenario: Each agent module is independently requireable
- **WHEN** any of the 10 agent modules is required
- **THEN** it SHALL return a valid `AgentDef` table without error
- **AND** requiring one agent SHALL NOT cause other agents to be loaded

#### Scenario: No side effects on require
- **WHEN** any agent module is required
- **THEN** no `vim.notify`, no `vim.fn.executable` check, no global state mutation SHALL occur

### Requirement: All-agents convenience module
neph.nvim SHALL provide `lua/neph/agents/all.lua` that returns an array of all agent definition tables.

#### Scenario: Require all agents
- **WHEN** `require("neph.agents.all")` is called
- **THEN** it SHALL return an array containing all 10 agent definition tables
