## ADDED Requirements

### Requirement: Local CI passes with task ci
Running `task ci` locally SHALL execute all lint and test tasks successfully, including Lua tests, TypeScript tests, and all new integration tests.

#### Scenario: task ci succeeds locally
- **WHEN** a developer runs `task ci` in the project root with the nix devShell active
- **THEN** all lint tasks (stylua, luacheck, tsc, deno lint) SHALL pass
- **AND** all test tasks (plenary busted, vitest neph-cli, vitest pi, vitest lib) SHALL pass

### Requirement: Dagger CI passes remotely
The Dagger pipeline SHALL complete successfully in both local (`task dagger`) and GitHub Actions environments.

#### Scenario: GitHub Actions CI succeeds
- **WHEN** a push or pull request triggers the CI workflow
- **THEN** the Dagger pipeline SHALL install all dependencies, run all lint and test tasks without failure

#### Scenario: Local dagger succeeds
- **WHEN** a developer runs `task dagger` locally with Docker and Dagger installed
- **THEN** the pipeline SHALL complete with the same results as the remote run

### Requirement: npm dependencies install cleanly
All `npm ci` commands SHALL succeed for every tool directory with a package.json.

#### Scenario: Clean install in container
- **WHEN** the Dagger pipeline runs `npm ci` for neph-cli, pi, and lib directories
- **THEN** dependencies SHALL install without errors (amp and opencode are standalone files, no npm ci needed)

### Requirement: New tests included in CI
All new vitest test files SHALL be automatically picked up by the task runner.

#### Scenario: Gate command tests run in CI
- **WHEN** `task tools:test:neph` runs
- **THEN** gate command tests SHALL be included in the vitest run

#### Scenario: Lib module tests run in CI
- **WHEN** `task tools:test` runs
- **THEN** neph-run lib tests SHALL be executed

### Requirement: Lint covers new code
All new TypeScript files SHALL be covered by lint tasks.

#### Scenario: Adapter TypeScript is type-checked
- **WHEN** `task lint` runs
- **THEN** amp and opencode TypeScript files SHALL be type-checked via `tsc --noEmit`
