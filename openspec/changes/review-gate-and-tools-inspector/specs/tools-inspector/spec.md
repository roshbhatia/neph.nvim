## ADDED Requirements

### Requirement: tools.status() returns per-agent install state
`lua/neph/internal/tools.lua` SHALL expose `M.status(root, agents)` returning a table keyed by agent name. Each entry SHALL contain: `{ has_tools: boolean, installed: boolean, pending: string[], missing: string[] }`. `pending` lists items whose fingerprint is stale; `missing` lists items whose target path does not exist. If an agent has no `tools` field, `has_tools` SHALL be `false` and `installed` SHALL be `true` (nothing to install).

#### Scenario: Agent with no tools manifest
- **WHEN** `tools.status(root, { goose_agent })` is called and goose has no `tools` field
- **THEN** returns `{ goose = { has_tools = false, installed = true, pending = {}, missing = {} } }`

#### Scenario: Agent with installed tools
- **WHEN** all symlinks and merges for an agent are in place and fingerprints are current
- **THEN** `installed == true` and `pending == {}` and `missing == {}`

#### Scenario: Agent with missing symlink
- **WHEN** a symlink target path does not exist on disk
- **THEN** `installed == false` and the symlink dst appears in `missing`

---

### Requirement: NephStatus buffer shows install state and runtime pipeline
`:NephStatus` (and `<leader>jn`) SHALL open a floating buffer displaying a table with one row per configured agent. Each row SHALL show: agent name, integration group, tools install status (`● installed` / `✗ missing` / `— none required`), and resolved review_provider. The buffer SHALL include the current gate state at the top.

#### Scenario: Status buffer opens
- **WHEN** `api.tools_status()` is called
- **THEN** a floating buffer opens with one row per agent
- **AND** the gate state line appears at the top

#### Scenario: Missing tools shown with action hint
- **WHEN** an agent has `installed == false`
- **THEN** the row shows `✗ not installed` with a hint line `→ run :NephInstall <name>`

---

### Requirement: NephInstall command installs tools for one or all agents
`:NephInstall` (no args) SHALL install tools for all agents that have a `tools` manifest. `:NephInstall <name>` SHALL install for a single named agent. Installation SHALL call the existing `tools.install_agent(root, agent)` function. On completion, a notification SHALL confirm success or surface any error.

#### Scenario: Install all
- **WHEN** `:NephInstall` is run
- **THEN** `tools.install_agent` is called for each agent with a tools manifest
- **AND** a summary notification shows how many agents were installed

#### Scenario: Install single agent
- **WHEN** `:NephInstall claude` is run
- **THEN** `tools.install_agent` is called only for the claude agent

#### Scenario: Install with no tools manifest
- **WHEN** `:NephInstall goose` is run and goose has no tools manifest
- **THEN** a notification says "goose: no tools to install"

---

### Requirement: NephInstall --preview shows dry-run diff
`:NephInstall --preview` (and `api.tools_preview()`) SHALL display what would be installed without making filesystem changes. The output SHALL list symlinks to be created, JSON merge keys to be added, and builds to be run.

#### Scenario: Preview shows pending changes
- **WHEN** `:NephInstall --preview` is run with an agent that has missing symlinks
- **THEN** a buffer opens listing the pending symlinks with `+` prefix (would be created)
- **AND** no filesystem changes are made
