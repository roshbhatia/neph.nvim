## ADDED Requirements

### Requirement: Explicit review provider registration
The Neovim review provider SHALL only be enabled when explicitly registered in `neph.setup()`.

#### Scenario: Review provider not configured
- **WHEN** the user does not register a review provider
- **THEN** the system SHALL use the `noop` review provider
- **AND** write tools SHALL proceed without opening a review UI

#### Scenario: Review provider configured
- **WHEN** the user registers the Neovim review provider in `neph.setup()`
- **THEN** review requests SHALL open the diff-hunk UI in Neovim

### Requirement: Review provider does not alter policy decisions
The review provider SHALL only refine decisions after policy evaluation.

#### Scenario: Policy denies
- **WHEN** the policy engine returns `deny`
- **THEN** the review provider SHALL NOT open a review UI
