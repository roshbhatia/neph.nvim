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

### Requirement: Filesystem watcher lifecycle

The system SHALL provide a `fs_watcher` module that watches project files for changes and triggers post-write review diffs when an agent is active.

#### Scenario: Watcher starts when agent session opens

- **WHEN** `session.open("goose")` succeeds
- **AND** `config.review.fs_watcher.enable` is true
- **THEN** the fs_watcher SHALL begin watching files in the current project root
- **AND** the watcher SHALL use `vim.uv.new_fs_event` for each watched file

#### Scenario: Watcher stops when all agent sessions close

- **WHEN** the last active agent session is killed
- **AND** no `vim.g.{name}_active` is set for any agent
- **THEN** the fs_watcher SHALL stop all active watches and release resources

#### Scenario: Watcher does not start when disabled

- **WHEN** `config.review.fs_watcher.enable` is false
- **THEN** no filesystem watches SHALL be created regardless of agent activity

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

### Requirement: Post-write review flow

The post-write review SHALL reuse the existing review engine with buffer-vs-disk diff.

#### Scenario: User opens post-write review

- **WHEN** the user acts on a post-write review notification
- **THEN** the review UI SHALL open with left=buffer contents (before) and right=disk contents (after)
- **AND** the user SHALL be able to accept/reject individual hunks

#### Scenario: Accept all in post-write review

- **WHEN** the user accepts all hunks in a post-write review
- **THEN** the buffer SHALL be updated to match the file on disk (equivalent to `:checktime` for that file)
- **AND** no file write SHALL occur (disk already has the content)

#### Scenario: Reject all in post-write review

- **WHEN** the user rejects all hunks in a post-write review
- **THEN** the buffer contents SHALL be written to disk (reverting the agent's changes)

#### Scenario: Partial accept in post-write review

- **WHEN** the user accepts some hunks and rejects others
- **THEN** the final content SHALL be computed by the review engine (accepted hunks from disk, rejected hunks from buffer)
- **AND** the final content SHALL be written to disk
- **AND** the buffer SHALL be updated to match

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
