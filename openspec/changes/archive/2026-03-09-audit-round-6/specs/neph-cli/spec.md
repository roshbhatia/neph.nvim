## ADDED Requirements

### Requirement: readStdin rejections are caught

#### Scenario: readStdin() throws during stdin reading
- **WHEN** `readStdin()` rejects (e.g., stream error)
- **THEN** the error is logged to stderr and process exits with code 1
