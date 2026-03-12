## MODIFIED Requirements

### Requirement: Pending requests cleared on disconnect

When `disconnect()` is called or the connection drops, all entries in `pendingRequests` SHALL be rejected and the map cleared. This prevents memory leaks from orphaned callbacks.

#### Scenario: Disconnect with pending requests

- **GIVEN** 3 requests are pending in the map
- **WHEN** `disconnect()` is called
- **THEN** all 3 pending request promises are rejected with a disconnect error
- **AND** `pendingRequests` map is empty

### Requirement: Reconnect timer cleared on explicit disconnect

When `disconnect()` is called, any active `reconnectTimer` SHALL be cleared immediately.

#### Scenario: Disconnect during reconnect backoff

- **GIVEN** a reconnect timer is scheduled (backoff)
- **WHEN** `disconnect()` is called
- **THEN** the reconnect timer is cleared
- **AND** no reconnect attempt fires after disconnect
