## ADDED Requirements

### Requirement: neph tools status shows per-agent install state
`neph tools status` SHALL call `tools.status()` in Neovim via RPC (when socket available) and print a table of agents with their install state. `neph tools status --offline` SHALL skip the RPC call and check filesystem state directly without querying Neovim.

#### Scenario: Online status
- **WHEN** `neph tools status` is run with a valid socket
- **THEN** a table is printed with one row per agent showing name, group, and install state

#### Scenario: Offline flag skips RPC
- **WHEN** `neph tools status --offline` is run
- **THEN** filesystem checks are performed without calling Neovim
- **AND** runtime pipeline column is omitted from output

---

### Requirement: neph tools install installs agent tools from CLI
`neph tools install [agent-name]` SHALL call `tools.install_agent()` for the specified agent (or all agents if no name given). On success it SHALL notify Neovim via RPC so the status buffer refreshes. On failure it SHALL print the error and exit non-zero.

#### Scenario: Install all agents
- **WHEN** `neph tools install` is run
- **THEN** install runs for all agents with tools manifests
- **AND** Neovim is notified on completion

#### Scenario: Install single agent by name
- **WHEN** `neph tools install claude` is run
- **THEN** only claude's tools are installed

---

### Requirement: neph tools preview shows dry-run diff without changes
`neph tools preview [agent-name]` SHALL print what would be installed/removed without modifying the filesystem. Output SHALL use `+` for items to be created and `-` for items to be removed.

#### Scenario: Preview pending symlinks
- **WHEN** `neph tools preview` is run and claude has an uninstalled symlink
- **THEN** output contains `+ symlink: <dst>` for that symlink
- **AND** no files are created or modified
