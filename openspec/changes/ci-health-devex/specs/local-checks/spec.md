## ADDED Requirements

### Requirement: Pre-push hook runs fast checks
A `.githooks/pre-push` script SHALL run `task check` before allowing a push. The `check` task SHALL complete in under 5 seconds for a clean codebase.

#### Scenario: Push blocked by lint error
- **WHEN** a developer pushes with a stylua violation
- **THEN** the push is rejected with the stylua error output

#### Scenario: Clean push proceeds
- **WHEN** all checks pass
- **THEN** the push proceeds normally

### Requirement: Task check includes TypeScript type checking
The `task check` target SHALL run `tsc --noEmit` for neph-cli in addition to stylua and luacheck, providing type-level feedback without requiring a full build.

#### Scenario: Type error caught locally
- **WHEN** a developer introduces a TypeScript type error in neph-cli
- **THEN** `task check` fails with the tsc error before they push
