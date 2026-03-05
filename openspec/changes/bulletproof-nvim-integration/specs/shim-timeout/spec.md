## ADDED Requirements

### Requirement: shimRun applies a timeout to non-interactive calls
`shimRun` in `pi.ts` SHALL accept an optional `timeoutMs` parameter. When provided and finite, it MUST terminate the child process and reject the promise after that many milliseconds. The default SHALL be `SHIM_TIMEOUT_MS` (15 000 ms).

#### Scenario: shimRun resolves before timeout
- **WHEN** the shim child exits with code 0 within the timeout window
- **THEN** the promise resolves with stdout as a string

#### Scenario: shimRun rejects after timeout
- **WHEN** the shim child does not exit within `timeoutMs` milliseconds
- **THEN** the child process is killed and the promise rejects with a timeout error message

#### Scenario: Preview calls shimRun with no timeout
- **WHEN** `preview()` calls `shimRun(["preview", filePath], content)`
- **THEN** no `timeoutMs` is passed so no timeout timer is set, allowing indefinite user interaction

### Requirement: NvimRPC socket has a configurable read timeout
`NvimRPC.__init__` in `shim.py` SHALL accept an optional `timeout: float | None` parameter (default `30.0`). When not `None`, it MUST call `self._sock.settimeout(timeout)` immediately after connecting.

#### Scenario: Default timeout applied
- **WHEN** `NvimRPC` is instantiated without a `timeout` argument
- **THEN** the socket's timeout is set to 30 seconds

#### Scenario: No timeout for preview
- **WHEN** `cmd_preview` instantiates `NvimRPC`
- **THEN** it passes `timeout=None`, leaving the socket in blocking mode with no deadline

#### Scenario: Socket raises on hung nvim
- **WHEN** the socket does not receive data within the timeout window
- **THEN** a `TimeoutError` propagates out of `request()`, causing the shim process to exit non-zero

#### Scenario: Commands other than preview use default timeout
- **WHEN** `cmd_open`, `cmd_checktime`, `cmd_set`, `cmd_unset`, `cmd_revert`, or `cmd_close_tab` are invoked
- **THEN** they connect with the default 30-second timeout
