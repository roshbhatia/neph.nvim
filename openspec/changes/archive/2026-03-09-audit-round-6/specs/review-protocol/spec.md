## ADDED Requirements

### Requirement: Post-write file writes check for errors

When `_apply_post_write` writes content to disk (reject revert or partial merge), write errors must be detected and reported to the user.

#### Scenario: Disk write fails during reject revert
- **WHEN** the reject path calls `f:write()` to revert agent changes
- **AND** the write fails (disk full, permission denied)
- **THEN** the file is closed, user is notified via vim.notify(ERROR), and the function returns early

#### Scenario: Disk write fails during partial merge
- **WHEN** the partial merge path calls `f:write()` to write merged content
- **AND** the write fails
- **THEN** the file is closed, user is notified via vim.notify(ERROR), and the function returns early
