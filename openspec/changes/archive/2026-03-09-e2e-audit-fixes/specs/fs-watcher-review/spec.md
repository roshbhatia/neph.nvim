## ADDED Requirements

### Requirement: Debug introspection API

The fs_watcher SHALL expose a function to list currently watched files for debugging and testing.

#### Scenario: get_watches returns watched paths

- **WHEN** `fs_watcher.get_watches()` is called
- **AND** files `a.lua` and `b.ts` are being watched
- **THEN** the function SHALL return a list containing those two file paths

#### Scenario: get_watches returns empty when inactive

- **WHEN** `fs_watcher.get_watches()` is called
- **AND** the watcher is not active
- **THEN** the function SHALL return an empty list

## MODIFIED Requirements

### Requirement: Watch target selection

The fs_watcher SHALL watch individual files, not recursive directories.

#### Scenario: Open buffers are watched

- **WHEN** the fs_watcher is active
- **AND** the user has `foo.lua` and `bar.ts` open in Neovim buffers within the project root
- **THEN** both files SHALL be watched for changes

#### Scenario: Reviewed files are watched

- **WHEN** a review completes for `/project/src/utils.lua`
- **THEN** `/project/src/utils.lua` SHALL be added to the watch list if not already watched

#### Scenario: Files outside project root are not watched

- **WHEN** a buffer is open for `/etc/hosts`
- **AND** the project root is `/home/user/project`
- **THEN** `/etc/hosts` SHALL NOT be watched

#### Scenario: Ignored patterns are excluded

- **WHEN** a buffer is open for `node_modules/foo/index.js`
- **AND** `node_modules` is in `config.review.fs_watcher.ignore`
- **THEN** that file SHALL NOT be watched

#### Scenario: Watch count is capped at configurable limit

- **WHEN** the number of watched files reaches `config.review.fs_watcher.max_watched` (default 100)
- **THEN** no additional files SHALL be watched
- **AND** a debug log entry SHALL be written

### Requirement: Change detection and post-write review trigger

When a watched file changes on disk and an agent is active, the fs_watcher SHALL offer the user a post-write review.

#### Scenario: Agent file write detected

- **WHEN** a watched file changes on disk
- **AND** at least one agent has `vim.g.{name}_active` set
- **AND** the file's buffer contents differ from the file on disk
- **THEN** the fs_watcher SHALL show a notification: "Agent changed: {relative_path} — press <key> to review"

#### Scenario: User-initiated save does not trigger

- **WHEN** a watched file changes on disk
- **AND** the file's buffer contents match the file on disk (buffer was just saved)
- **THEN** no notification SHALL be shown

#### Scenario: File currently in review is ignored

- **WHEN** a watched file changes on disk
- **AND** that file is currently being reviewed in the review UI
- **THEN** the change SHALL be ignored (no duplicate review)

#### Scenario: Debounce rapid changes

- **WHEN** a watched file changes on disk multiple times within 200ms
- **THEN** only one notification SHALL be generated for the final state

#### Scenario: File deleted between watch event and read

- **WHEN** a watched file triggers a change event
- **AND** the file has been deleted before the debounced read occurs
- **THEN** the watcher SHALL log a debug message and skip the review
- **AND** no error SHALL be raised

### Requirement: Configuration

The fs_watcher SHALL be configurable via `neph.Config`.

#### Scenario: Default configuration

- **WHEN** no `review.fs_watcher` config is provided
- **THEN** the fs_watcher SHALL be enabled with default ignore patterns: `node_modules`, `.git`, `dist`, `build`, `__pycache__`
- **AND** `max_watched` SHALL default to 100

#### Scenario: Custom ignore patterns

- **WHEN** `config.review.fs_watcher.ignore` is set to `{ "vendor", ".cache" }`
- **THEN** files matching those patterns SHALL be excluded from watching

#### Scenario: Custom max_watched

- **WHEN** `config.review.fs_watcher.max_watched` is set to 50
- **THEN** the watch count cap SHALL be 50 instead of 100
