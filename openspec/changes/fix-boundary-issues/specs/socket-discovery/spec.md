## ADDED Requirements

### Requirement: Socket discovery with heuristic scoring
The socket discovery system SHALL use heuristic scoring to resolve ambiguous cases in monorepos. The system SHALL maintain conservative defaults while improving user experience.

#### Scenario: Single socket discovery
- **WHEN** only one Neovim socket exists
- **THEN** discovery SHALL return that socket path
- **AND** SHALL not require cwd or git root matching

#### Scenario: Multiple sockets with different git roots
- **WHEN** multiple Neovim sockets exist with different git roots
- **AND** CLI's git root matches one socket's git root
- **THEN** discovery SHALL return the matching socket
- **AND** SHALL ignore sockets with different git roots

#### Scenario: Multiple sockets with same git root (monorepo)
- **WHEN** multiple Neovim sockets exist with same git root
- **AND** CLI cwd is a subdirectory of one socket's cwd
- **THEN** discovery SHALL return the socket whose cwd is a prefix of CLI cwd
- **AND** SHALL use directory depth as tie-breaker for closest match

#### Scenario: Ambiguous monorepo case
- **WHEN** multiple sockets exist with same git root
- **AND** CLI cwd doesn't prefix-match any socket cwd
- **THEN** discovery SHALL return null
- **AND** SHALL require explicit NVIM_SOCKET_PATH

#### Scenario: No sockets found
- **WHEN** no Neovim sockets exist
- **THEN** discovery SHALL return null
- **AND** dry-run mode SHALL be triggered if enabled

### Requirement: Conservative fallback behavior
Socket discovery SHALL err on the side of caution when ambiguity exists. The system SHALL not guess incorrectly when multiple valid options exist.

#### Scenario: Ambiguity threshold
- **WHEN** heuristic scoring produces multiple candidates with similar scores
- **AND** score difference is below ambiguity threshold
- **THEN** discovery SHALL return null
- **AND** SHALL require explicit NVIM_SOCKET_PATH

#### Scenario: Minimum score requirement
- **WHEN** best candidate score is below minimum threshold
- **THEN** discovery SHALL return null
- **AND** SHALL treat as "no clear match"

### Requirement: Cross-platform socket pattern matching
Socket discovery SHALL work across different operating systems and temporary directory patterns.

#### Scenario: macOS/Linux temporary paths
- **WHEN** running on macOS or Linux
- **THEN** discovery SHALL search `/tmp/nvim.*/0` patterns
- **AND** SHALL handle Neovim's socket naming conventions

#### Scenario: macOS var/folders paths
- **WHEN** running on macOS
- **THEN** discovery SHALL search `/var/folders/*/*/T/nvim.*/*/nvim.*.0` patterns
- **AND** SHALL parse PID from directory names

#### Scenario: Process validation
- **WHEN** a socket file is found
- **THEN** discovery SHALL validate that the corresponding process exists
- **AND** SHALL skip sockets for dead processes
- **AND** SHALL use process.kill(pid, 0) for validation

### Requirement: Git root computation
Socket discovery SHALL compute git roots accurately for matching logic. Git root computation SHALL handle edge cases.

#### Scenario: Git repository root
- **WHEN** computing git root for a directory
- **THEN** system SHALL run `git rev-parse --show-toplevel`
- **AND** SHALL handle non-git directories by returning null
- **AND** SHALL handle git command errors gracefully

#### Scenario: Symlinked git directories
- **WHEN** directory contains symlinks to git repository
- **THEN** git root computation SHALL resolve symlinks
- **AND** SHALL return canonical path

#### Scenario: Submodule git roots
- **WHEN** directory is inside a git submodule
- **THEN** git root SHALL return submodule root, not parent repository root
- **AND** SHALL match Neovim's git root computation