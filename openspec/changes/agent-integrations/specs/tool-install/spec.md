## MODIFIED Requirements

### Requirement: Auto-symlink on setup
neph.nvim's `M.setup()` SHALL install all bundled tool files to their expected locations, creating parent directories as needed. This includes:
- `tools/neph-cli/dist/index.js` to `~/.local/bin/neph` (symlink)
- `tools/pi/package.json` to `~/.pi/agent/extensions/nvim/package.json` (symlink)
- `tools/pi/dist` to `~/.pi/agent/extensions/nvim/dist` (symlink)
- `tools/copilot/hooks.json` — NOT auto-installed (Copilot requires project-level `.github/hooks/hooks.json` committed to default branch; documented for manual copy)
- `tools/cursor/hooks.json` to `~/.cursor/hooks.json` (symlink)
- `tools/claude/settings.json` to `~/.claude/settings.json` (JSON merge — hooks key only)
- `tools/gemini/settings.json` to `~/.gemini/settings.json` (JSON merge — hooks key only)
- `tools/amp/neph-plugin.ts` to `~/.config/amp/plugins/neph-plugin.ts` (symlink)
- `tools/opencode/write.ts` to `~/.config/opencode/tools/write.ts` (symlink)
- `tools/opencode/edit.ts` to `~/.config/opencode/tools/edit.ts` (symlink)

#### Scenario: Symlinks created on first setup
- **WHEN** `require("neph").setup()` is called and the tool files exist
- **THEN** `~/.local/bin/neph` is a symlink pointing to `tools/neph-cli/dist/index.js`
- **AND** pi extension symlinks are created
- **AND** hook config files are installed for all supported agents

#### Scenario: Symlinks are force-updated
- **WHEN** `require("neph").setup()` is called and symlinks already exist
- **THEN** the existing symlinks are replaced (`ln -sf`) without error

#### Scenario: Missing tool file is skipped with warning
- **WHEN** `require("neph").setup()` is called but a tool file is not found
- **THEN** no symlink is created for that file
- **THEN** a `vim.notify` warning is emitted indicating the missing file

#### Scenario: JSON merge preserves existing settings
- **WHEN** `require("neph").setup()` is called and `~/.claude/settings.json` already exists with user settings
- **THEN** only the `hooks` key SHALL be merged into the existing file
- **AND** all other settings SHALL be preserved

#### Scenario: JSON merge creates new file if none exists
- **WHEN** `require("neph").setup()` is called and no `~/.claude/settings.json` exists
- **THEN** the full config file SHALL be written
