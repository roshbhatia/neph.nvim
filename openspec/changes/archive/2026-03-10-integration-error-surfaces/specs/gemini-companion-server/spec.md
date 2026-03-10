## ADDED Requirements

### Requirement: Missing sidecar script notification

The companion module SHALL notify the user when the sidecar script is not found, rather than failing silently.

#### Scenario: Companion script not built

- **WHEN** `companion.start_sidecar()` is called
- **AND** `tools/gemini/dist/companion.js` does not exist
- **THEN** the system SHALL call `vim.notify("Neph: Gemini companion not built — run :NephTools install gemini", ERROR)`
- **AND** SHALL return nil without starting a job

#### Scenario: Companion script exists

- **WHEN** `companion.start_sidecar()` is called
- **AND** `tools/gemini/dist/companion.js` exists
- **THEN** no error notification SHALL be shown
- **AND** the sidecar SHALL start normally

### Requirement: Sidecar respawn with exponential backoff

The companion sidecar SHALL retry with exponential backoff and a retry cap instead of retrying indefinitely at a fixed interval.

#### Scenario: First respawn uses 2s delay

- **WHEN** the sidecar exits with non-zero code for the first time
- **AND** `vim.g.gemini_active` is set
- **THEN** the respawn SHALL be scheduled after 2000ms

#### Scenario: Subsequent respawns double the delay

- **WHEN** the sidecar exits with non-zero code for the Nth time
- **AND** N is 2 or 3
- **THEN** the respawn SHALL be scheduled after `2000 * 2^(N-1)` ms

#### Scenario: Respawn stops after 3 attempts

- **WHEN** the sidecar has failed 3 times
- **THEN** no further respawn SHALL be attempted
- **AND** the system SHALL call `vim.notify("Neph: Gemini companion failed to start after 3 attempts", ERROR)`

#### Scenario: Successful start resets retry counter

- **WHEN** the sidecar starts successfully (exits with code 0 or stays running)
- **THEN** the retry counter SHALL be reset to 0
