## MODIFIED Requirements

### Requirement: Protocol contract

The dispatch table SHALL be validated against `protocol.json`.

#### Scenario: Contract test

- **WHEN** running `tests/contract_spec.lua`
- **THEN** every method in `protocol.json` SHALL have a corresponding handler in the dispatch table
- **AND** every handler in the dispatch table SHALL be listed in `protocol.json`
- **AND** `bus.register` SHALL be present in `protocol.json` with params `["agent", "channel_id"]`
