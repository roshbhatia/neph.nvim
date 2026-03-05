## ADDED Requirements

### Requirement: Vitest suite exists for pi.ts
`tools/pi/tests/pi.test.ts` SHALL exist and be runnable via `npm test` from `tools/pi/`.

#### Scenario: Tests pass
- **WHEN** `npm test` is run from `tools/pi/`
- **THEN** all test cases pass with exit code 0

### Requirement: shimRun tests
`shimRun` (the internal spawn wrapper) SHALL be tested via a mocked `spawn`.

#### Scenario: shimRun resolves with stdout on success
- **WHEN** the mocked spawn emits stdout data `"hello"` and closes with code 0
- **THEN** `shimRun(["status"])` resolves with `"hello"`

#### Scenario: shimRun rejects on non-zero exit
- **WHEN** the mocked spawn emits stderr data `"error msg"` and closes with code 1
- **THEN** `shimRun(["status"])` rejects with an error containing `"error msg"`

#### Scenario: shimRun writes stdin when provided
- **WHEN** `shimRun(["preview", "/file"], "content")` is called
- **THEN** the mocked child's `stdin.write` is called with `"content"`

### Requirement: preview() tests
`preview()` SHALL be tested for accept, reject, and error paths.

#### Scenario: preview returns accept result
- **WHEN** shimRun resolves with `'{"decision":"accept","content":"final"}'`
- **THEN** `preview("/file", "proposed")` resolves with `{ decision: "accept", content: "final" }`

#### Scenario: preview returns reject result
- **WHEN** shimRun resolves with `'{"decision":"reject","reason":"too noisy"}'`
- **THEN** `preview("/file", "proposed")` resolves with `{ decision: "reject", reason: "too noisy" }`

#### Scenario: preview returns reject on shimRun error
- **WHEN** shimRun rejects with any error
- **THEN** `preview("/file", "proposed")` resolves with `{ decision: "reject", reason: "Preview failed or timed out" }`

### Requirement: write tool override tests
The registered `write` tool SHALL call preview and either write the accepted content or reject.

#### Scenario: write tool writes accepted content
- **WHEN** `preview` returns `{ decision: "accept", content: "final content" }`
- **THEN** `createWriteTool().execute` is called with the accepted content
- **THEN** the tool result contains no rejection message

#### Scenario: write tool rejects and reverts
- **WHEN** `preview` returns `{ decision: "reject", reason: "nope" }`
- **THEN** `createWriteTool().execute` is NOT called
- **THEN** shim is called with `["revert", filePath]`
- **THEN** the tool result text contains `"Write rejected: nope"`

#### Scenario: write tool surfaces partial rejection notes
- **WHEN** `preview` returns `{ decision: "accept", content: "ok", reason: "hunk 2 skipped" }`
- **THEN** the tool result includes a note text containing `"hunk 2 skipped"`

### Requirement: edit tool override tests
The registered `edit` tool SHALL handle missing file, oldText not found, accept, and reject.

#### Scenario: edit tool returns error when file cannot be read
- **WHEN** `readFileSync` throws for the given path
- **THEN** the tool result text contains `"Cannot read"`

#### Scenario: edit tool returns error when oldText not found
- **WHEN** the file content does not include `oldText`
- **THEN** the tool result text contains `"Edit failed"`
- **THEN** `preview` is NOT called

#### Scenario: edit tool applies accepted diff
- **WHEN** `preview` returns `{ decision: "accept", content: "updated" }`
- **THEN** `createWriteTool().execute` is called with the accepted content

#### Scenario: edit tool rejects and reverts
- **WHEN** `preview` returns `{ decision: "reject", reason: "bad change" }`
- **THEN** shim is called with `["revert", filePath]`
- **THEN** the tool result text contains `"Edit rejected: bad change"`

### Requirement: Lifecycle event tests
Event handlers SHALL be no-ops when `NVIM_SOCKET_PATH` is absent and active when present.

#### Scenario: session_start no-op without socket
- **WHEN** `NVIM_SOCKET_PATH` is not set and `session_start` fires
- **THEN** shim is NOT called
- **THEN** `registerTool` is NOT called

#### Scenario: session_start registers tools with socket
- **WHEN** `NVIM_SOCKET_PATH` is set and `session_start` fires
- **THEN** shim is called with `["set", "pi_active", "true"]`
- **THEN** `pi.registerTool` is called for `"write"` and `"edit"`

#### Scenario: session_shutdown cleans up globals
- **WHEN** `NVIM_SOCKET_PATH` is set and `session_shutdown` fires
- **THEN** shim is called with `["close-tab"]`
- **THEN** shim is called with `["unset", "pi_active"]`
- **THEN** shim is called with `["unset", "pi_running"]`

#### Scenario: agent_end triggers checktime and close-tab
- **WHEN** `NVIM_SOCKET_PATH` is set and `agent_end` fires
- **THEN** shim is called with `["unset", "pi_running"]`
- **THEN** shim is called with `["checktime"]`
- **THEN** shim is called with `["close-tab"]`

#### Scenario: tool_call opens file on read
- **WHEN** `NVIM_SOCKET_PATH` is set and `tool_call` fires with `toolName = "read"` and `input.path = "/foo"`
- **THEN** shim is called with `["open", "/foo"]`
