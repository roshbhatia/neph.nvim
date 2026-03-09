## ADDED Requirements

### Requirement: openDiff tool implementation
The companion SHALL implement the `openDiff` MCP tool that displays proposed file changes in Neovim's vimdiff review interface.

#### Scenario: openDiff triggers vimdiff review
- **WHEN** Gemini CLI calls `openDiff` with `filePath` and `newContent`
- **THEN** the companion SHALL call `neph.review(filePath, newContent)` via NephClient
- **AND** Neovim SHALL open the vimdiff review UI for the user

#### Scenario: openDiff returns success
- **WHEN** `openDiff` is called and the review UI opens successfully
- **THEN** the MCP tool response SHALL return an empty content array (`content: []`)

#### Scenario: openDiff returns error for invalid file
- **WHEN** `openDiff` is called with a `filePath` that cannot be resolved
- **THEN** the MCP tool response SHALL return `isError: true` with a descriptive error message

#### Scenario: openDiff handles new file creation
- **WHEN** `openDiff` is called with a `filePath` that does not exist on disk
- **THEN** the companion SHALL treat the current content as empty
- **AND** open the vimdiff review showing the full `newContent` as additions

### Requirement: closeDiff tool implementation
The companion SHALL implement the `closeDiff` MCP tool that closes an open diff view and returns the file's final content.

#### Scenario: closeDiff returns current file content
- **WHEN** Gemini CLI calls `closeDiff` with `filePath`
- **THEN** the companion SHALL read the file's current content from disk
- **AND** return it as a TextContent block in the MCP response

#### Scenario: closeDiff for file with no open diff
- **WHEN** `closeDiff` is called for a file that has no active diff view
- **THEN** the companion SHALL still return the file's current content
- **AND** SHALL NOT return an error

### Requirement: diffAccepted notification
The companion SHALL send an `ide/diffAccepted` notification to Gemini CLI when the user accepts changes in the review UI.

#### Scenario: Full accept sends notification
- **WHEN** the user accepts all hunks in the vimdiff review
- **AND** the ReviewEnvelope has `decision: "accept"`
- **THEN** the companion SHALL send `ide/diffAccepted` with `filePath` and the final `content`

#### Scenario: Partial accept sends notification with edited content
- **WHEN** the user accepts some hunks and rejects others
- **AND** the ReviewEnvelope has `decision: "partial"`
- **THEN** the companion SHALL send `ide/diffAccepted` with `filePath` and the merged final `content`
- **AND** the content SHALL reflect only the accepted hunks

### Requirement: diffRejected notification
The companion SHALL send an `ide/diffRejected` notification to Gemini CLI when the user rejects all changes.

#### Scenario: Full reject sends notification
- **WHEN** the user rejects all hunks in the vimdiff review
- **AND** the ReviewEnvelope has `decision: "reject"`
- **THEN** the companion SHALL send `ide/diffRejected` with `filePath`

### Requirement: Review result drives file writes
The companion SHALL write accepted content to disk after a successful review, since Gemini CLI expects the IDE to apply accepted diffs.

#### Scenario: Accepted content written to disk
- **WHEN** the ReviewEnvelope decision is "accept" or "partial"
- **THEN** the companion SHALL write the final content to `filePath` on disk
- **AND** SHALL call `neph.checktime()` to refresh Neovim buffers

#### Scenario: Rejected content not written
- **WHEN** the ReviewEnvelope decision is "reject"
- **THEN** the companion SHALL NOT write anything to disk
