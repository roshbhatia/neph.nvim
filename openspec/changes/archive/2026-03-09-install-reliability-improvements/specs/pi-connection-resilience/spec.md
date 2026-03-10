## ADDED Requirements

### Requirement: Exponential backoff with jitter
The system SHALL use exponential backoff with random jitter when reconnecting to avoid thundering herd.

#### Scenario: First reconnect uses minimal delay
- **WHEN** connection drops for the first time
- **THEN** reconnect attempt happens after 100ms + random jitter (0-50ms)

#### Scenario: Backoff increases on repeated failures
- **WHEN** three reconnect attempts fail
- **THEN** fourth attempt waits 800ms + jitter (exponential: 100 → 200 → 400 → 800)

#### Scenario: Backoff caps at maximum delay
- **WHEN** reconnect backoff exceeds 5 seconds
- **THEN** subsequent attempts wait 5000ms + jitter (capped)

### Requirement: Explicit connection lifecycle
The system SHALL expose connection state (connecting, connected, disconnected, reconnecting) to pi extension event handlers.

#### Scenario: Session start waits for connection
- **WHEN** `session_start` event fires
- **THEN** extension attempts connection and registers with bus only after connected

#### Scenario: Failed connection retries automatically
- **WHEN** initial connection fails
- **THEN** extension enters reconnecting state and retries with backoff

#### Scenario: Manual disconnect stops reconnect
- **WHEN** `session_shutdown` fires
- **THEN** extension disconnects and sets state to prevent reconnect

### Requirement: Bus heartbeat monitoring
The system SHALL send periodic heartbeat pings (neph:ping) to detect dead channels and unregister automatically.

#### Scenario: Dead channel detected within 3 seconds
- **WHEN** a pi channel stops responding to pings
- **THEN** bus unregisters the channel within 3 ping cycles (3 seconds)

#### Scenario: Reconnected agent re-registers automatically
- **WHEN** pi reconnects after channel death
- **THEN** agent calls `bus.register` again and receives new prompts

### Requirement: Connection error logging
The system SHALL log all connection events (connect, disconnect, reconnect attempts, failures) to neph debug log.

#### Scenario: Connection failure logged with reason
- **WHEN** connection attempt fails
- **THEN** debug log contains "neph-client: connection failed: <reason>"

#### Scenario: Successful reconnect logged
- **WHEN** reconnect succeeds after failures
- **THEN** debug log contains "neph-client: reconnected successfully"

### Requirement: Graceful degradation on connection loss
The system SHALL queue review operations and retry when connection is restored, avoiding blocking tool execution.

#### Scenario: Review queued during disconnect
- **WHEN** `write` tool is called while disconnected
- **THEN** review operation queues and retries when connection restores (with timeout)

#### Scenario: Review timeout after 30 seconds
- **WHEN** connection remains down for 30+ seconds during review
- **THEN** tool returns "reject" decision with reason "connection timeout"
