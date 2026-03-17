## ADDED Requirements

### Requirement: Canonical integration event
The integration pipeline SHALL normalize agent-specific events into a canonical event envelope.

#### Scenario: Adapter normalizes tool call
- **WHEN** an agent adapter receives a tool event
- **THEN** it SHALL emit a canonical event including `agent`, `event`, `tool`, `input`, and `cwd`

### Requirement: Canonical decision envelope
Pipeline stages SHALL exchange a canonical decision envelope.

#### Scenario: Policy engine returns a decision envelope
- **WHEN** the policy engine evaluates a canonical event
- **THEN** it SHALL return `{ decision, reason?, updated_input? }` where `decision` is `allow|deny|ask|modify`

### Requirement: Mandatory policy engine stage
Every integration pipeline SHALL include a policy engine stage, with `noop` as the default.

#### Scenario: No policy engine configured
- **WHEN** an integration pipeline is resolved without an explicit policy engine
- **THEN** the system SHALL insert the `noop` policy engine
- **AND** `noop` SHALL return `allow` with no `updated_input`

### Requirement: Response formatting is isolated
Response formatting SHALL be the only stage that knows agent-specific response schemas.

#### Scenario: Formatter emits agent response
- **WHEN** a canonical decision envelope is produced
- **THEN** the formatter SHALL translate it into the agent’s required output format
