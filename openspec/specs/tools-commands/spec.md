## ADDED Requirements

### Requirement: NephTools user command with subcommands

The plugin SHALL register a `:NephTools` user command with subcommands `install`, `uninstall`, `reinstall`, and `status`. The command SHALL provide tab completion for both subcommands and agent names.

#### Scenario: Install all agents

- **WHEN** the user runs `:NephTools install all`
- **THEN** tools are installed for the universal neph-cli and all agents whose executable is on PATH
- **AND** agents not on PATH are reported as skipped
- **AND** per-agent results are displayed (success, failure with reason, or skipped)

#### Scenario: Install a specific agent

- **WHEN** the user runs `:NephTools install pi`
- **THEN** pi's tools are installed regardless of whether `pi` is on PATH
- **AND** results are displayed showing each operation (symlinks, builds, files)

#### Scenario: Install with no argument defaults to all

- **WHEN** the user runs `:NephTools install`
- **THEN** it behaves the same as `:NephTools install all`

#### Scenario: Uninstall a specific agent

- **WHEN** the user runs `:NephTools uninstall claude`
- **THEN** claude's hook entries are removed from `~/.claude/settings.json`
- **AND** results are displayed confirming removal

#### Scenario: Uninstall all

- **WHEN** the user runs `:NephTools uninstall all`
- **THEN** all agent symlinks are removed, JSON merges are reversed, and created files are deleted
- **AND** the universal neph-cli symlink is removed

#### Scenario: Reinstall

- **WHEN** the user runs `:NephTools reinstall pi`
- **THEN** pi's tools are uninstalled and then installed fresh
- **AND** the agent's stamp file is cleared

#### Scenario: Status with no argument

- **WHEN** the user runs `:NephTools status`
- **THEN** a summary is displayed showing each agent's install state: installed, not on PATH, no tools, or error
- **AND** the universal neph-cli status is shown first

#### Scenario: Status for a specific agent

- **WHEN** the user runs `:NephTools status pi`
- **THEN** detailed information is shown: symlink paths and validity, build artifact existence, file creation status

#### Scenario: Tab completion

- **WHEN** the user types `:NephTools ` and presses tab
- **THEN** completion offers `install`, `uninstall`, `reinstall`, `status`
- **AND** after a subcommand, completion offers `all` plus all registered agent names
