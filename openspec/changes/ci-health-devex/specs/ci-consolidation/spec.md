## ADDED Requirements

### Requirement: Single CI job replaces parallel jobs
CI SHALL run lint, test, and e2e as sequential steps within a single job, entering the nix shell once and executing all steps inside it.

#### Scenario: All checks pass in single job
- **WHEN** a push or PR triggers CI
- **THEN** a single job runs: npm ci for all tools, lint, test (including pi), and e2e, in that order

#### Scenario: Lint failure stops pipeline early
- **WHEN** stylua or luacheck finds an issue
- **THEN** the job fails immediately without running tests or e2e

### Requirement: Concurrency control cancels stale runs
CI SHALL use a concurrency group keyed on `ci-${{ github.ref }}` with `cancel-in-progress: true` so that new pushes to the same branch cancel any in-flight run.

#### Scenario: Rapid pushes cancel old runs
- **WHEN** two pushes happen to the same branch within seconds
- **THEN** the first CI run is cancelled and only the second runs to completion

### Requirement: Pi tests are included in CI
The `tools/Taskfile.yml` SHALL include a `test:pi` task that runs `npx vitest --run` in the pi directory, and `tools/pi/package.json` SHALL have a `"test"` script. The `test` task SHALL depend on `test:pi`.

#### Scenario: Pi test failure fails CI
- **WHEN** a pi test fails
- **THEN** the CI job exits non-zero

### Requirement: Nix flake lock is pinned
CI SHALL NOT use `--no-write-lock-file`. A committed `flake.lock` file SHALL be used for reproducible builds. Updates to nixpkgs SHALL be explicit via `nix flake update`.

#### Scenario: Deterministic nix environment
- **WHEN** CI runs on two different days without a flake.lock change
- **THEN** the same neovim version, node version, and tool versions are used

### Requirement: CI status badge in README
The project README SHALL display a CI status badge linking to the workflow.

#### Scenario: Badge reflects current status
- **WHEN** CI passes on main
- **THEN** the badge shows a passing status
