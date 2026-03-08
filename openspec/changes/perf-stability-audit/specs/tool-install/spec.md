## MODIFIED Requirements

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
