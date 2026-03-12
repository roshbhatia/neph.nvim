## CHANGED Requirements

### Requirement: HTTP body size limit counts bytes not characters

The companion HTTP server body size check SHALL count raw bytes, not string length after decoding, to prevent multi-byte UTF-8 bypass.

#### Scenario: Multi-byte UTF-8 bypass

- **WHEN** an HTTP request body contains multi-byte UTF-8 characters
- **AND** the byte length exceeds 1MB but the character count does not
- **THEN** the server SHALL still reject the request with HTTP 413
- **AND** SHALL destroy the request stream

### Requirement: Tool handler errors use JSON-RPC error format

The MCP tool handlers SHALL return errors using JSON-RPC 2.0 error format with code -32603 (Internal error).

#### Scenario: Tool handler throws

- **WHEN** a tool handler (e.g., openDiff, closeDiff) throws or rejects
- **THEN** the response SHALL be a JSON-RPC 2.0 error with `code: -32603`
- **AND** the `message` field SHALL contain a descriptive error string

### Requirement: closeDiff validates filePath type

The closeDiff tool handler SHALL validate that `filePath` is a string before processing.

#### Scenario: filePath is not a string

- **WHEN** the closeDiff tool is called
- **AND** `filePath` is not a string (undefined, number, object, etc.)
- **THEN** the handler SHALL return a JSON-RPC 2.0 error
- **AND** SHALL NOT attempt any file operations
