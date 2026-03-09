## MODIFIED Requirements

### Requirement: Auto-symlink on setup

neph.nvim's `M.setup()` SHALL defer tool installation to a UIEnter autocmd. The install SHALL check per-agent stamp files and skip agents whose stamps are fresh. When install runs, it SHALL iterate injected agents' `tools` manifests and process symlinks, merges, builds, and files using pure Lua operations. Each agent's install SHALL be independent — one agent's failure SHALL NOT prevent other agents from installing. Symlinks and file operations SHALL use Lua APIs (`vim.uv.fs_symlink`, `vim.fn.writefile`). npm builds SHALL use `vim.fn.jobstart` as separate per-build jobs.

#### Scenario: Symlinks created via Lua

- **WHEN** `tools.install_async()` runs and agents have `tools.symlinks` manifests
- **THEN** symlinks are created using `vim.uv.fs_symlink()` (or `os.execute("ln -sfn ...")` as fallback)
- **AND** each symlink operation reports success or failure independently

#### Scenario: Merges processed from agent manifests

- **WHEN** `tools.install_async()` runs and agents have `tools.merges` manifests
- **THEN** JSON merges are performed for each agent's declared merges

#### Scenario: Builds processed as independent jobs

- **WHEN** `tools.install_async()` runs and agents have `tools.builds` manifests
- **THEN** each build is a separate `vim.fn.jobstart` invocation
- **AND** a failing build for one agent does not prevent other agents from installing
- **AND** the failing agent's error is reported with context (agent name, exit code)

#### Scenario: Files created from agent manifests

- **WHEN** `tools.install_async()` runs and agents have `tools.files` manifests
- **THEN** files are created according to the declared mode (create_only or overwrite)

#### Scenario: Per-agent stamp files

- **WHEN** agent claude is installed successfully
- **THEN** a stamp file is written at `~/.local/share/nvim/neph_install_claude.stamp`
- **AND** subsequent startups skip claude's install if the stamp is fresh

#### Scenario: One agent failure does not block others

- **WHEN** pi's npm build fails but claude's merge succeeds
- **THEN** claude's stamp is written and claude is considered installed
- **AND** pi's stamp is NOT written so pi retries on next startup
- **AND** an error is reported for pi with the failure reason

#### Scenario: tools.lua contains zero agent names

- **WHEN** `lua/neph/tools.lua` is read
- **THEN** it SHALL NOT contain any hardcoded agent names (pi, claude, cursor, amp, opencode, gemini, etc.)
- **AND** the only hardcoded tool path SHALL be `neph-cli` (universal)

### Requirement: Tools bundled in repo

neph.nvim SHALL include agent-specific tool files in the `tools/` directory. Each agent's tool manifest references paths relative to this directory. The `tools/neph-cli/` directory contains the universal neph CLI.

#### Scenario: Tools present after clone

- **WHEN** a user clones or installs neph.nvim via a plugin manager
- **THEN** the `tools/` directory SHALL contain agent-specific subdirectories referenced by agent manifests

### Requirement: JSON unmerge for clean uninstall

The tools module SHALL provide a `json_unmerge(src_path, dst_path, key)` function that removes entries from the destination file that match entries in the source file. Matching SHALL use the same `matcher` + `hooks[1].command` criteria as `hook_entry_exists`.

#### Scenario: Unmerge claude hooks

- **WHEN** `json_unmerge("claude/settings.json", "~/.claude/settings.json", "hooks")` is called
- **AND** the destination file contains neph-added hook entries
- **THEN** only the matching hook entries are removed
- **AND** user-added entries that don't match are preserved
- **AND** the file is written back without the removed entries

#### Scenario: Unmerge on file that has no matching entries

- **WHEN** `json_unmerge` is called and no entries in dst match src
- **THEN** the destination file is not modified
