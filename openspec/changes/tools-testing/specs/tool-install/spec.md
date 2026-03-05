## MODIFIED Requirements

### Requirement: nvim-shim is not symlinked
`tools/core/nvim-shim` SHALL be removed from the repository entirely. `tools.lua` SHALL NOT reference it, and `tools/README.md` SHALL NOT document it.

#### Scenario: nvim-shim absent from repo
- **WHEN** the repo is checked out
- **THEN** `tools/core/nvim-shim` does not exist

#### Scenario: tools.lua symlink table does not reference nvim-shim
- **WHEN** `lua/neph/tools.lua` is read
- **THEN** there is no reference to `nvim-shim` in the symlink TOOLS table
