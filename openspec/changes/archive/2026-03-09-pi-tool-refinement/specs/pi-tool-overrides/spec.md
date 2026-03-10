## ADDED Requirements

### Requirement: Pi Tool Overrides
The `pi` extension SHALL override the built-in `write` and `edit` tools to insert an interactive Neovim review step before any file mutation.

#### Scenario: Intercepted write
- **WHEN** the agent calls the `write` tool
- **THEN** the override SHALL call `neph.review` with the proposed content
- **AND** if the user accepts, it SHALL delegate to the original `createWriteTool`
- **AND** if the user rejects, it SHALL return an error message to the agent

#### Scenario: Intercepted edit
- **WHEN** the agent calls the `edit` tool
- **THEN** the override SHALL call `neph.review` with the reconstructed full file content
- **AND** if the user accepts, it SHALL delegate to the original `createEditTool`
- **AND** if the user rejects, it SHALL return an error message to the agent

#### Scenario: Delegate validation
- **WHEN** an intercepted tool is accepted by the user
- **THEN** the override SHALL NOT perform manual file existence or string matching checks
- **AND** SHALL rely on the underlying tool's native validation during delegation
