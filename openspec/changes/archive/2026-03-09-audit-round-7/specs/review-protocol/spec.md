## ADDED Requirements

### Requirement: Review open validates file_path parameter

#### Scenario: Review opened with nil or empty file_path
- **WHEN** `review.open` is called with `params.path` that is nil, non-string, or empty string
- **THEN** it returns `{ok=false, error="invalid file_path"}` without performing any file operations
