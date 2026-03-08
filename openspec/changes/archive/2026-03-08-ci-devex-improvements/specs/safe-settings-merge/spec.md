## ADDED Requirements

### Requirement: Additive hook merge
The `json_merge()` function in tools.lua SHALL append neph's hooks to the destination file's existing hooks array rather than replacing the entire key.

#### Scenario: Existing hooks preserved
- **WHEN** `~/.claude/settings.json` already contains hooks configured by the user
- **AND** `tools.install()` runs
- **THEN** the user's existing hooks SHALL remain in the file alongside neph's hooks

#### Scenario: Neph hooks added if missing
- **WHEN** `~/.claude/settings.json` has no hooks matching neph's matchers
- **AND** `tools.install()` runs
- **THEN** neph's hooks SHALL be appended to the hooks arrays

#### Scenario: Duplicate hooks not added
- **WHEN** neph's hooks already exist in the destination file (same matcher and command)
- **AND** `tools.install()` runs
- **THEN** no duplicate entries SHALL be created (idempotent)

#### Scenario: Non-hook keys untouched
- **WHEN** the destination settings file contains keys other than hooks
- **AND** `tools.install()` runs
- **THEN** all non-hook keys SHALL remain unchanged
