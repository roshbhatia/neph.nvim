## ADDED Requirements

### Requirement: Group defaults for integrations
The system SHALL support integration groups that define default pipeline dependencies.

#### Scenario: Agent resolves group defaults
- **WHEN** an agent is assigned to an integration group
- **THEN** its pipeline SHALL inherit the group’s default policy engine, review provider, and formatter

### Requirement: Per-agent overrides
Agents SHALL be able to override any group-provided pipeline dependency.

#### Scenario: Agent overrides group review provider
- **WHEN** an agent configuration specifies a review provider override
- **THEN** the pipeline SHALL use the agent override instead of the group default

### Requirement: Group dependency tree reporting
Integration status SHALL surface the dependency tree derived from group defaults and overrides.

#### Scenario: Status reports resolved dependencies
- **WHEN** integration status is requested for an agent
- **THEN** the output SHALL include resolved policy engine, review provider, and formatter sources (group or override)
