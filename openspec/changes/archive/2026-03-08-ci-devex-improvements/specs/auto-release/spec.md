## ADDED Requirements

### Requirement: Conventional commit enforcement
The CI pipeline SHALL validate that PR titles or commit messages follow the Conventional Commits specification (feat, fix, chore, etc.).

#### Scenario: Valid conventional commit passes
- **WHEN** a commit message is "feat: add new agent support"
- **THEN** the commit lint check SHALL pass

#### Scenario: Invalid commit message fails
- **WHEN** a commit message is "added stuff"
- **THEN** the commit lint check SHALL fail with a descriptive error

### Requirement: Automated release via release-please
A release-please workflow SHALL run on pushes to main and maintain a release PR with changelog updates.

#### Scenario: Feature commit triggers release PR
- **WHEN** a `feat:` commit is pushed to main
- **THEN** release-please SHALL create or update a release PR with a minor version bump and changelog entry

#### Scenario: Fix commit triggers release PR
- **WHEN** a `fix:` commit is pushed to main
- **THEN** release-please SHALL create or update a release PR with a patch version bump and changelog entry

#### Scenario: Release PR merge creates GitHub release
- **WHEN** the release-please PR is merged
- **THEN** a GitHub Release SHALL be created with the new version tag and changelog body
