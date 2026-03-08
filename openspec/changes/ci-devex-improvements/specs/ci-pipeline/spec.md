## ADDED Requirements

### Requirement: Direct Nix CI without Dagger
The CI pipeline SHALL use `cachix/install-nix-action` and `nix develop -c` directly in GitHub Actions, without Dagger or FluentCI.

#### Scenario: CI runs lint via Nix
- **WHEN** a push or PR triggers CI
- **THEN** the lint job SHALL execute `nix develop -c task lint` directly in the GHA runner

#### Scenario: CI runs tests via Nix
- **WHEN** a push or PR triggers CI
- **THEN** the test job SHALL execute `nix develop -c task test` directly in the GHA runner

### Requirement: Parallel CI jobs
The CI pipeline SHALL run lint, unit tests, and e2e tests as separate parallel jobs.

#### Scenario: Jobs run concurrently
- **WHEN** CI is triggered
- **THEN** lint, test, and e2e jobs SHALL start simultaneously (no sequential dependencies between them)

#### Scenario: Any job failure fails the pipeline
- **WHEN** any one of lint, test, or e2e fails
- **THEN** the overall CI status SHALL be reported as failed

### Requirement: Nix store caching
The CI pipeline SHALL cache the Nix store between runs to avoid re-downloading derivations.

#### Scenario: Cached Nix store reused
- **WHEN** CI runs and the flake inputs have not changed
- **THEN** `nix develop` SHALL use cached derivations and complete in under 30 seconds

### Requirement: snacks.nvim available in CI
The Nix dev shell SHALL include snacks.nvim so that e2e agent launch tests can exercise the native backend.

#### Scenario: snacks.nvim loadable in CI
- **WHEN** nvim starts in the CI environment
- **THEN** `require("snacks")` SHALL succeed without error
