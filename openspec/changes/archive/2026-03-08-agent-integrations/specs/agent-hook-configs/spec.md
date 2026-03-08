## ADDED Requirements

### Requirement: Claude Code PreToolUse hook config
neph.nvim SHALL include a Claude Code hook configuration file at `tools/claude/settings.json` that intercepts `Edit` and `Write` tool calls via the `PreToolUse` event, pointing to `neph gate --agent claude`.

#### Scenario: Hook config has correct structure
- **WHEN** `tools/claude/settings.json` is parsed
- **THEN** it SHALL contain a `hooks.PreToolUse` array with a matcher `"Edit|Write"` and command `"neph gate --agent claude"`

#### Scenario: Hook config is valid JSON
- **WHEN** `tools/claude/settings.json` is parsed by the test suite
- **THEN** it SHALL parse without errors

### Requirement: Copilot preToolUse hook config
neph.nvim SHALL include a Copilot hook configuration file at `tools/copilot/hooks.json` that intercepts `edit` and `create` tool calls via the `preToolUse` event, pointing to `neph gate --agent copilot`.

#### Scenario: Hook config has correct structure
- **WHEN** `tools/copilot/hooks.json` is parsed
- **THEN** it SHALL contain a preToolUse hook entry with command `"neph gate --agent copilot"`

#### Scenario: Hook config is valid JSON
- **WHEN** `tools/copilot/hooks.json` is parsed by the test suite
- **THEN** it SHALL parse without errors

### Requirement: Cursor post-write hook config
neph.nvim SHALL include a Cursor hook configuration file at `tools/cursor/hooks.json` that observes file edits via the `afterFileEdit` event, pointing to `neph gate --agent cursor`. Because Cursor's hook is **informational only** (cannot block writes), this integration SHALL call `checktime` and manage statusline state only — NOT gate writes through review.

#### Scenario: Hook config has correct structure
- **WHEN** `tools/cursor/hooks.json` is parsed
- **THEN** it SHALL contain an `afterFileEdit` hook entry with command `"neph gate --agent cursor"`

#### Scenario: Hook config is valid JSON
- **WHEN** `tools/cursor/hooks.json` is parsed by the test suite
- **THEN** it SHALL parse without errors

#### Scenario: Cursor gate does NOT run review
- **WHEN** `neph gate --agent cursor` receives an afterFileEdit event
- **THEN** it SHALL call `checktime` and update statusline state
- **AND** it SHALL NOT attempt a review (exit 0 immediately)

### Requirement: Gemini BeforeTool hook config
neph.nvim SHALL include a Gemini hook configuration file at `tools/gemini/settings.json` that intercepts file write tool calls via the `BeforeTool` event, pointing to `neph gate --agent gemini`.

#### Scenario: Hook config has correct structure
- **WHEN** `tools/gemini/settings.json` is parsed
- **THEN** it SHALL contain a `hooks.BeforeTool` array with command `"neph gate --agent gemini"`

#### Scenario: Hook config is valid JSON
- **WHEN** `tools/gemini/settings.json` is parsed by the test suite
- **THEN** it SHALL parse without errors

### Requirement: Hook configs installed by tools.lua
`tools.lua` SHALL install hook config files to their agent-specific locations during `setup()`. For agents with shared settings files (claude, gemini), installation SHALL merge the `hooks` key into the existing file rather than overwriting it.

#### Scenario: Standalone hook file installed
- **WHEN** `setup()` runs and `tools/copilot/hooks.json` exists
- **THEN** it SHALL be symlinked to the appropriate copilot hooks location

#### Scenario: Shared settings file merged
- **WHEN** `setup()` runs and the user already has `~/.claude/settings.json` with other settings
- **THEN** only the `hooks` key SHALL be merged, preserving all other settings

#### Scenario: Fresh install writes full config
- **WHEN** `setup()` runs and no existing settings file exists for the agent
- **THEN** the full config file SHALL be written

### Requirement: Terminal-only agents have no hook config
Agents without hook support (goose, codex, crush) SHALL NOT have hook configuration files.

#### Scenario: No directories for unsupported agents
- **WHEN** the `tools/` directory is inspected
- **THEN** there SHALL be no `tools/goose/`, `tools/codex/`, or `tools/crush/` directories containing hook configs
