## ADDED Requirements

### Requirement: Review open validates file_path parameter

The `review.open` handler SHALL validate that the `file_path` parameter is a non-empty string before processing.

#### Scenario: file_path is nil, non-string, or empty

- **WHEN** `review.open` is called with `file_path` that is nil, a non-string type, or an empty string
- **THEN** the handler SHALL return `{ ok = false, error = "invalid file_path" }`
- **AND** no review UI SHALL open
