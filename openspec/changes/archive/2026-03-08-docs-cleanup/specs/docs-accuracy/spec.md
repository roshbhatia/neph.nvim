## ADDED Requirements

### Requirement: AGENTS.md reflects constructor injection architecture
AGENTS.md SHALL describe the current setup pattern where agents and backends are injected via `setup()` as explicit Lua values. It SHALL NOT reference `multiplexer` config, `internal/backends/` directory, hardcoded agent lists, `merge()` function, or tmux/zellij stubs.

#### Scenario: Code organization tree matches filesystem
- **WHEN** a contributor reads the Code Organization section
- **THEN** the tree shows `lua/neph/agents/*.lua`, `lua/neph/backends/*.lua`, `lua/neph/internal/contracts.lua`, and does not show `lua/neph/internal/backends/`

#### Scenario: Agent registration section shows submodule pattern
- **WHEN** a contributor reads the Agent Registration section
- **THEN** it describes agents as submodules at `lua/neph/agents/<name>.lua` returning `AgentDef` tables, not as entries in a hardcoded list

#### Scenario: Adding a new agent guide is correct
- **WHEN** a contributor follows the "Adding a New Agent" guide
- **THEN** the guide instructs them to create a file at `lua/neph/agents/<name>.lua`, add it to `all.lua`, and pass it in `setup()` — not to edit `internal/agents.lua`

#### Scenario: Adding a new backend guide is correct
- **WHEN** a contributor follows the "Adding a New Backend" guide
- **THEN** the guide instructs them to create a file at `lua/neph/backends/<name>.lua` implementing the backend interface, and pass it as `backend` in `setup()`

#### Scenario: Installation example uses DI pattern
- **WHEN** a contributor reads the installation example
- **THEN** the example shows `agents = { require("neph.agents.claude"), ... }` and `backend = require("neph.backends.snacks")`

#### Scenario: Gotchas section is current
- **WHEN** a contributor reads the gotchas
- **THEN** there are no references to `multiplexer`, `internal/backends/`, or `full_cmd` runtime computation, and there is a gotcha about contract validation failing loud at setup time

### Requirement: docs/testing.md covers all test suites
docs/testing.md SHALL list every test file in the `tests/` directory with a brief description of what it covers.

#### Scenario: All Lua test suites are documented
- **WHEN** a contributor reads docs/testing.md
- **THEN** they find entries for: contracts_spec, agent_submodules_spec, backend_conformance_spec, setup_smoke_spec, agents_spec, config_spec, session_spec, placeholders_spec, context_spec, history_spec, and the review engine/contract specs

#### Scenario: Test commands are accurate
- **WHEN** a contributor runs the test commands listed in docs/testing.md
- **THEN** the commands execute successfully against the current Taskfile

### Requirement: docs/rpc-protocol.md matches protocol.json
docs/rpc-protocol.md SHALL list exactly the methods defined in `protocol.json` with correct parameter names and types.

#### Scenario: Method list is complete
- **WHEN** a contributor compares docs/rpc-protocol.md to protocol.json
- **THEN** every method in protocol.json appears in the doc, and no extra methods are listed

### Requirement: Module docstrings are accurate
EmmyLua `@mod` and `@brief` annotations in Lua source files SHALL NOT reference removed concepts (multiplexer, internal/backends/, hardcoded agent list, merge()).

#### Scenario: Key module docstrings match reality
- **WHEN** a contributor reads the `@brief` annotation at the top of `init.lua`, `config.lua`, `agents.lua`, `session.lua`, or `tools.lua`
- **THEN** the description matches the current behavior of that module
