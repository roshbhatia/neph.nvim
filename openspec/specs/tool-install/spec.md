## MODIFIED Requirements

### Requirement: neph-cli is agent-independent

The neph-cli build and symlink SHALL remain in `tools.lua` as universal infrastructure not associated with any agent. The symlink to `~/.local/bin/neph` SHALL only be created when explicitly requested via `:NephTools install all` or `:NephTools install neph-cli`. The automatic `install_async()` at startup SHALL build neph-cli but SHALL skip the symlink creation.

#### Scenario: neph-cli built but not symlinked at startup

- **WHEN** `tools.install_async()` runs at Neovim startup
- **THEN** `tools/neph-cli/dist/index.js` SHALL be built if sources are newer than artifact
- **AND** the symlink to `~/.local/bin/neph` SHALL NOT be created automatically

#### Scenario: Explicit install creates symlink

- **WHEN** the user runs `:NephTools install all`
- **THEN** the symlink from `tools/neph-cli/dist/index.js` to `~/.local/bin/neph` SHALL be created
- **AND** the neph-cli SHALL be built if not already current

#### Scenario: Agents using launch_args_fn use absolute paths

- **WHEN** an agent's `launch_args_fn` generates a hook command referencing neph-cli
- **THEN** the command SHALL use `node <plugin_root>/tools/neph-cli/dist/index.js` (absolute path)
- **AND** the command SHALL NOT depend on `neph` being on PATH

#### Scenario: os.rename failure is logged and surfaced

- **WHEN** `os.rename(tmp_path, target_path)` fails during fingerprint or transaction file writes
- **THEN** the error SHALL be logged at WARN level
- **AND** the enclosing function SHALL return false or an error indicator
- **AND** the plugin SHALL NOT crash

#### Scenario: Symlink destination validated against project root

- **WHEN** `tools.lua` processes a `sym_spec.dst` path via `vim.fn.expand()`
- **THEN** the resolved absolute path SHALL be validated to start with the project root or `$HOME`
- **AND** if the path escapes those boundaries, the symlink SHALL be skipped with a WARN log
