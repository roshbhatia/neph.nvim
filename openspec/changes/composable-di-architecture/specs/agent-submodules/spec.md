## ADDED Requirements

### Requirement: Agent definition submodules
neph.nvim SHALL provide standalone Lua modules under `lua/neph/agents/` where each module returns a single `AgentDef` table. Modules SHALL have no side effects on require.

#### Scenario: Require claude agent
- **WHEN** `require("neph.agents.claude")` is called
- **THEN** it SHALL return a table with `name = "claude"`, `label = "Claude"`, `cmd = "claude"`, `icon` (string), and `args` (string array)

#### Scenario: Require pi agent with send_adapter
- **WHEN** `require("neph.agents.pi")` is called
- **THEN** it SHALL return a table with `name = "pi"` and a `send_adapter` function
- **AND** the `send_adapter` function SHALL match the existing pi send behavior (set `vim.g.neph_pending_prompt`)

#### Scenario: Each agent module is independently requireable
- **WHEN** any of `require("neph.agents.claude")`, `require("neph.agents.goose")`, `require("neph.agents.opencode")`, `require("neph.agents.amp")`, `require("neph.agents.copilot")`, `require("neph.agents.gemini")`, `require("neph.agents.codex")`, `require("neph.agents.crush")`, `require("neph.agents.cursor")`, `require("neph.agents.pi")` is called
- **THEN** it SHALL return a valid `AgentDef` table without error
- **AND** requiring one agent SHALL NOT cause other agents to be loaded

#### Scenario: No side effects on require
- **WHEN** `require("neph.agents.claude")` is called
- **THEN** no `vim.notify`, no `vim.fn.executable` check, no global state mutation SHALL occur

### Requirement: All-agents convenience module
neph.nvim SHALL provide `lua/neph/agents/all.lua` that returns an array of all agent definition tables.

#### Scenario: Require all agents
- **WHEN** `require("neph.agents.all")` is called
- **THEN** it SHALL return an array containing all 10 agent definition tables

#### Scenario: All agents are valid
- **WHEN** `require("neph.agents.all")` is called
- **THEN** every element in the returned array SHALL pass `contracts.validate_agent()`
