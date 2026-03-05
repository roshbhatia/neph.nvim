## MODIFIED Requirements

### Requirement: Timeout applied via socket.setdefaulttimeout before pynvim.attach
`shim.py` SHALL apply the connection timeout by calling
`socket.setdefaulttimeout(timeout)` immediately before `pynvim.attach(...)`,
and SHALL reset it to `None` immediately after the attach call returns.
The default timeout for all commands except `cmd_preview` SHALL be `30.0` seconds.
`cmd_preview` SHALL pass `timeout=None` (no timeout) since it blocks on user input.

#### Scenario: Default 30s timeout set before attach for non-preview commands
- **WHEN** `get_nvim()` is called without an explicit timeout argument
- **THEN** `socket.setdefaulttimeout(30.0)` is called before `pynvim.attach`

#### Scenario: No timeout set for preview command
- **WHEN** `get_nvim(timeout=None)` is called (as in `cmd_preview`)
- **THEN** `socket.setdefaulttimeout(None)` is called before `pynvim.attach`

#### Scenario: Timeout reset after attach
- **WHEN** `get_nvim()` completes successfully
- **THEN** `socket.setdefaulttimeout` is restored (called with `None` after attach returns)
