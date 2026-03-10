## ADDED Requirements

### Requirement: HTTP body size limit counts bytes not characters

The MCP server body size limit must track incoming bytes accurately to prevent multi-byte UTF-8 payloads from bypassing the limit.

#### Scenario: Multi-byte UTF-8 payload exceeds byte limit
- **WHEN** an HTTP request sends a body with multi-byte characters
- **AND** the total byte count exceeds MAX_BODY
- **THEN** the request is rejected with 413 even if character count is under the limit

### Requirement: Tool handler errors use JSON-RPC error format

When a tool handler throws, the error response must use the JSON-RPC error object format, not the tool result format.

#### Scenario: Tool handler throws an error
- **WHEN** a registered tool handler throws during execution
- **THEN** the response uses JSON-RPC error format with code -32603 (Internal error)

### Requirement: closeDiff validates filePath type

#### Scenario: closeDiff called with non-string filePath
- **WHEN** closeDiff receives a non-string filePath parameter
- **THEN** it returns an error result without attempting file operations
