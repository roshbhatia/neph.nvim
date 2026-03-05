## ADDED Requirements

### Requirement: shim CLI uses Click for command dispatch
`shim.py` SHALL use Click `@click.group()` / `@cli.command()` decorators instead of manual `sys.argv` parsing and `match` dispatch. Each subcommand SHALL declare its arguments via `@click.argument()`.

#### Scenario: --help works at group and command level
- **WHEN** `shim --help` or `shim preview --help` is invoked
- **THEN** Click prints auto-generated usage text and exits 0

#### Scenario: Unknown command exits with error
- **WHEN** `shim bogus-command` is invoked
- **THEN** Click exits non-zero with "No such command" in stderr

#### Scenario: Missing required argument exits with error
- **WHEN** `shim open` is invoked without a FILE argument
- **THEN** Click exits non-zero with "Missing argument" in stderr

#### Scenario: All existing commands remain functional
- **WHEN** any of `status`, `open`, `preview`, `revert`, `close-tab`, `checktime`, `set`, `unset` are invoked with correct arguments
- **THEN** they behave identically to the pre-Click implementation

### Requirement: click>=8.0 is declared as a dependency
The inline script metadata (`# dependencies`) in `shim.py` SHALL include `click>=8.0`.

#### Scenario: uv resolves click
- **WHEN** `uv run shim.py --help` is invoked on a clean machine
- **THEN** uv installs click and the help text is printed without error
