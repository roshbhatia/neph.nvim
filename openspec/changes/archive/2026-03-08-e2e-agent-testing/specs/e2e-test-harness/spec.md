## ADDED Requirements

### Requirement: Headless neovim test runner
The system SHALL provide a Lua-based e2e test runner at `tests/e2e/run.lua` that executes via `nvim --headless -l tests/e2e/run.lua`.

#### Scenario: Runner exits with code 0 on all tests passing
- **WHEN** all e2e tests pass
- **THEN** the neovim process SHALL exit with code 0

#### Scenario: Runner exits with non-zero code on failure
- **WHEN** any e2e test fails or times out
- **THEN** the neovim process SHALL exit with code 1 and print the failing test name and reason to stderr

### Requirement: Plugin smoke test
The test runner SHALL verify that `require("neph").setup()` completes without error in a headless neovim instance.

#### Scenario: Plugin loads successfully
- **WHEN** the e2e runner executes the smoke test
- **THEN** `require("neph").setup()` SHALL return without error and `require("neph.internal.agents").get_all()` SHALL return a table

### Requirement: Tool installation verification
The test runner SHALL verify that `require("neph.tools").install()` creates expected symlinks and JSON merge files.

#### Scenario: Symlinks created for built tools
- **WHEN** `tools.install()` completes and `neph-cli/dist/index.js` exists
- **THEN** `~/.local/bin/neph` SHALL be a symlink pointing to the plugin's `tools/neph-cli/dist/index.js`

#### Scenario: JSON merge files created
- **WHEN** `tools.install()` completes and `tools/claude/settings.json` exists
- **THEN** `~/.claude/settings.json` SHALL contain the `hooks` key from the source settings

### Requirement: Agent launch test
The test runner SHALL verify that each installed agent can be opened in a terminal without crashing neovim. Each agent SHALL be tested in a separate `nvim --headless` invocation for isolation.

#### Scenario: Agent terminal opens successfully
- **WHEN** an agent's executable is on PATH
- **THEN** opening the agent via `session.open()` SHALL create a terminal buffer within 10 seconds and set `vim.g.<termname>_active` to true (for terminal-only agents) or defer to the agent's own status mechanism (for hook/extension agents)

#### Scenario: Agent not installed is skipped
- **WHEN** an agent's executable is NOT on PATH
- **THEN** the test SHALL be skipped with a warning, not counted as a failure

#### Scenario: Neovim survives agent open/close
- **WHEN** an agent terminal is opened and then closed
- **THEN** neovim SHALL still be running (not crashed or exited) after the close

### Requirement: Isolated test execution
Each agent-specific e2e test SHALL run in its own `nvim --headless` process to prevent cross-contamination.

#### Scenario: Crashing agent does not block other tests
- **WHEN** agent A's test causes neovim to exit unexpectedly
- **THEN** agent B's test SHALL still execute in a fresh neovim instance and report its own result

### Requirement: Timeout-based async assertions
The test harness SHALL use `vim.wait()` with configurable timeouts (default 10 seconds) for assertions that depend on async operations like terminal creation.

#### Scenario: Assertion succeeds within timeout
- **WHEN** the expected condition becomes true before the timeout
- **THEN** the test SHALL pass immediately without waiting for the full timeout

#### Scenario: Assertion fails on timeout
- **WHEN** the expected condition does not become true within the timeout
- **THEN** the test SHALL fail with a message including the condition description and timeout duration
