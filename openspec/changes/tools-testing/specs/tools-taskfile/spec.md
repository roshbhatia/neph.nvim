## ADDED Requirements

### Requirement: tools/Taskfile.yml defines test and lint tasks
`tools/Taskfile.yml` SHALL define `test`, `test:core`, `test:pi`, `lint:core`, and `lint:pi` tasks that run from their respective tool subdirectories.

#### Scenario: test:core runs pytest
- **WHEN** `task test:core` is run from `tools/`
- **THEN** `uv run pytest tests/ -v` is executed in the `tools/core/` directory

#### Scenario: test:pi runs npm test
- **WHEN** `task test:pi` is run from `tools/`
- **THEN** `npm test` is executed in the `tools/pi/` directory

#### Scenario: test runs both
- **WHEN** `task test` is run from `tools/`
- **THEN** both `test:core` and `test:pi` are run as dependencies

### Requirement: Root Taskfile includes tools/Taskfile.yml
The root `Taskfile.yml` SHALL include `tools/Taskfile.yml` via the `includes:` key with `dir: tools` so all tools tasks are available prefixed with `tools:`.

#### Scenario: tools:test available at root
- **WHEN** `task tools:test` is run from the repo root
- **THEN** the tools test suite runs without error

#### Scenario: Root test task depends on tools:test
- **WHEN** `task test` is run from the repo root
- **THEN** `tools:test` is also executed as part of the run
