## MODIFIED Requirements

### Requirement: Symlink validation resolves parent symlinks

Symlink destination validation SHALL use `vim.fn.resolve()` on both source and destination paths before checking prefix boundaries. This prevents path traversal through symlinked parent directories.

#### Scenario: Parent directory is a symlink

- **GIVEN** `~/.local/bin` is a symlink to `/tmp/bin`
- **WHEN** a tool install attempts to symlink to `~/.local/bin/tool`
- **THEN** the resolved path `/tmp/bin/tool` is validated
- **AND** the symlink is rejected (outside home directory)
