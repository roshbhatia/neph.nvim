## ADDED Requirements

### Requirement: HTTP request body size limit

The companion HTTP server SHALL reject requests with bodies exceeding 1MB.

#### Scenario: Request body exceeds limit

- **WHEN** an HTTP request body exceeds 1MB (1,048,576 bytes)
- **THEN** the server SHALL respond with HTTP 413 (Payload Too Large)
- **AND** SHALL destroy the request stream

#### Scenario: Request body within limit

- **WHEN** an HTTP request body is within 1MB
- **THEN** the request SHALL be processed normally
