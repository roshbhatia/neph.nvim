## NEW Requirements

### Requirement: NephReview command opens buffer-vs-disk review

The plugin SHALL provide a `:NephReview [file]` user command that opens an interactive hunk-by-hunk review comparing buffer contents (old) to disk contents (new).

#### Scenario: Review current buffer's file

- **WHEN** the user runs `:NephReview` with no arguments
- **AND** the current buffer is backed by a file
- **THEN** a review opens comparing buffer content to disk content
- **AND** the review uses `mode = "post_write"`

#### Scenario: Review a specific file

- **WHEN** the user runs `:NephReview /path/to/file.lua`
- **AND** the file exists on disk
- **THEN** a review opens for that file
- **AND** the buffer for that file is used as the "old" side

#### Scenario: File does not exist

- **WHEN** the user runs `:NephReview /nonexistent/file.lua`
- **THEN** an error notification is shown: "File not found"
- **AND** no review opens

#### Scenario: Current buffer has no file

- **WHEN** the user runs `:NephReview` on a scratch buffer
- **THEN** an error notification is shown: "Buffer has no file"
- **AND** no review opens

#### Scenario: Buffer matches disk (no changes)

- **WHEN** the user runs `:NephReview`
- **AND** buffer content is identical to disk content
- **THEN** a notification is shown: "No changes to review"
- **AND** no review opens

### Requirement: Manual reviews integrate with review queue

Manual reviews SHALL be enqueued via the review queue. If another review is active, the manual review is queued.

#### Scenario: Manual review while agent review is active

- **GIVEN** an agent-initiated review is active
- **WHEN** the user runs `:NephReview`
- **THEN** the manual review is queued
- **AND** a notification shows "Review queued"

### Requirement: Manual review results are local-only

Manual reviews SHALL NOT write result files or send RPC notifications. The result is applied locally (buffer/disk sync) and discarded.

#### Scenario: Manual review completes

- **WHEN** the user finishes a manual review
- **THEN** accepted hunks update the buffer to match disk
- **AND** no file is written to result_path
- **AND** no vim.rpcnotify is called

### Requirement: Public API function

`require("neph.api").review(path)` SHALL be available for programmatic access. Returns `{ok: boolean, msg?: string, error?: string}`.

#### Scenario: API call with valid path

- **WHEN** `require("neph.api").review("/path/to/file.lua")` is called
- **THEN** returns `{ok = true, msg = "Review started"}`
- **AND** a review opens

#### Scenario: API call with no path

- **WHEN** `require("neph.api").review()` is called
- **THEN** it uses the current buffer's file path
