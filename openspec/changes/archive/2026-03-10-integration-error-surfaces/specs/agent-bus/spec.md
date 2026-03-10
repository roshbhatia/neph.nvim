## ADDED Requirements

### Requirement: Bus-to-TTY fallback notification

The session module SHALL notify the user when an extension agent's prompt is sent via terminal instead of the agent bus.

#### Scenario: First fallback for an agent shows notification

- **WHEN** `session.send()` is called for an extension agent
- **AND** `bus.is_connected()` returns false
- **AND** no fallback notification has been shown for this agent in the current session
- **THEN** the system SHALL call `vim.notify("Neph: <agent> bus disconnected, using terminal fallback", WARN)`
- **AND** SHALL record that this agent has been notified

#### Scenario: Subsequent fallbacks are silent

- **WHEN** `session.send()` falls back to TTY for an agent
- **AND** a fallback notification has already been shown for this agent
- **THEN** no additional notification SHALL be shown

#### Scenario: Notification resets on re-registration

- **WHEN** an extension agent re-registers with the bus (via `bus.register()`)
- **THEN** the fallback notification flag SHALL be cleared for that agent
- **AND** future fallbacks SHALL trigger the notification again
