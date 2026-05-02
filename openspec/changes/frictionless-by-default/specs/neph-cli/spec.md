## ADDED Requirements

### Requirement: `neph context current` prints latest broadcast snapshot

The `neph` CLI SHALL expose a `context current` subcommand that reads `${XDG_STATE_HOME:-$HOME/.local/state}/nvim/neph/context.json` and prints the JSON to stdout. When the file is missing or older than a configurable staleness threshold, the command SHALL print a structured error to stderr and exit non-zero.

#### Scenario: Print fresh snapshot

- **WHEN** the broadcast file exists and was written within the staleness window (default 5s)
- **AND** the user runs `neph context current`
- **THEN** the command SHALL print the JSON contents to stdout
- **AND** SHALL exit with status 0

#### Scenario: Missing snapshot fails with clear error

- **WHEN** the broadcast file does not exist
- **AND** the user runs `neph context current`
- **THEN** the command SHALL print `{"error": "no_snapshot", "path": "<resolved-path>"}` to stderr
- **AND** SHALL exit with non-zero status

#### Scenario: Stale snapshot fails by default

- **WHEN** the broadcast file's `ts` is older than 5000ms
- **AND** the user runs `neph context current`
- **THEN** the command SHALL print `{"error": "stale_snapshot", "age_ms": <age>}` to stderr
- **AND** SHALL exit with non-zero status

#### Scenario: --max-age-ms overrides staleness threshold

- **WHEN** the user runs `neph context current --max-age-ms 60000`
- **AND** the broadcast file's `ts` is 30s old
- **THEN** the command SHALL print the snapshot to stdout (not treated as stale)
- **AND** SHALL exit with status 0

#### Scenario: --field selects a single key path

- **WHEN** the user runs `neph context current --field buffer.uri`
- **AND** the snapshot is fresh and contains a buffer URI
- **THEN** the command SHALL print only the buffer URI as a plain string to stdout (no JSON wrapping)
- **AND** SHALL exit with status 0
