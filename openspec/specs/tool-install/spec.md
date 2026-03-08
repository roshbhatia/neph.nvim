## MODIFIED Requirements

### Requirement: Tools bundled in repo
neph.nvim SHALL include `tools/core/shim.py` (Python) and `tools/pi/pi.ts` (TypeScript) as checked-in files in the repository `tools/` directory. `tools/core/nvim-shim` (bash) is no longer part of the documented or bundled tool set.

#### Scenario: Tools present after clone
- **WHEN** a user clones or installs neph.nvim via a plugin manager
- **THEN** `tools/core/shim.py` and `tools/pi/pi.ts` are present on disk under the plugin's install directory

### Requirement: Auto-symlink on setup
neph.nvim's `M.setup()` SHALL defer tool installation to a UIEnter autocmd. The install SHALL check a stamp file first and skip entirely if the plugin directory has not changed. When install runs, all filesystem operations (mkdir, ln, npm build) SHALL execute in a single background shell job via `vim.fn.jobstart()`.

#### Scenario: Symlinks created on first setup
- **WHEN** `require("neph").setup()` is called and no stamp file exists
- **THEN** symlinks are created asynchronously after UIEnter fires
- **AND** the Neovim event loop is not blocked during installation

#### Scenario: Stamp-based skip on subsequent startups
- **WHEN** `require("neph").setup()` is called and the stamp file is newer than the tools/ directory
- **THEN** no installation work is performed
- **AND** setup completes in under 1ms

#### Scenario: Symlinks are force-updated
- **WHEN** the tools/ directory is newer than the stamp file
- **THEN** symlinks are re-created via a background shell job
- **AND** the stamp file is touched after successful completion

## REMOVED Requirements

### Requirement: nvim-shim is not symlinked
**Reason**: `tools/core/nvim-shim` (bash wrapper) has been removed from the repo. There is no longer anything to symlink or document.
**Migration**: Use `shim.py` (auto-symlinked to `~/.local/bin/shim`) for all Neovim msgpack-rpc integration.
