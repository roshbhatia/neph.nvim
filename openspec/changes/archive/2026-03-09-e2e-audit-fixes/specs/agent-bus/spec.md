## MODIFIED Requirements

### Requirement: Connection health monitoring

The bus SHALL detect dead channels and clean up stale registrations. The bus SHALL NOT modify `vim.g` state — session.lua owns that responsibility.

#### Scenario: Dead channel detected and cleaned up

- **WHEN** agent "pi" is registered with channel 5
- **AND** channel 5 is no longer valid (agent process died)
- **THEN** the bus SHALL remove pi from the registry

#### Scenario: Health check is non-blocking

- **WHEN** the health check timer fires
- **THEN** it SHALL NOT block the Neovim event loop
- **AND** it SHALL complete in under 1ms for up to 10 registered agents

#### Scenario: Health check failure is logged

- **WHEN** `vim.rpcnotify()` fails for a registered channel
- **THEN** the bus SHALL log the failure at debug level via `log.debug("bus", ...)`
- **AND** the agent SHALL be unregistered from the bus
