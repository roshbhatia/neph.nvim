## ADDED Requirements

### Requirement: Build script compiles all TypeScript tools

A shell script `scripts/build.sh` SHALL compile `tools/neph-cli`, `tools/amp`, and `tools/pi` by running `npm ci && npm run build` in each package directory, then install the `~/.local/bin/neph` symlink.

#### Scenario: Successful build

- **WHEN** `scripts/build.sh` is executed in the plugin root
- **THEN** `tools/neph-cli/dist/index.js` SHALL be (re)created
- **AND** `tools/amp/dist/amp.js` SHALL be (re)created
- **AND** `tools/pi/dist/` SHALL be (re)created
- **AND** `~/.local/bin/neph` SHALL be symlinked to `tools/neph-cli/dist/index.js`
- **AND** the script SHALL exit 0

#### Scenario: npm not on PATH

- **WHEN** `npm` is not found on PATH
- **THEN** the script SHALL print an actionable error message
- **AND** the script SHALL exit non-zero
- **AND** existing `dist/` files SHALL be left unchanged

---

### Requirement: lazy.nvim build hook invokes the build script

The lazy.nvim plugin spec SHALL support both `build = 'bash scripts/build.sh'` (shell string) and `build = function() require('neph.build').run() end` (Lua function) variants. Both SHALL produce identical outcomes.

#### Scenario: lazy build on install

- **WHEN** the user installs neph.nvim via `:Lazy install`
- **AND** the lazy spec includes a `build` key
- **THEN** the build step SHALL run after the plugin files are placed
- **AND** `dist/` artifacts SHALL be current when `setup()` is called for the first time

#### Scenario: lazy build on update

- **WHEN** the user updates neph.nvim via `:Lazy update`
- **THEN** the build step SHALL run after new source is pulled
- **AND** `dist/` artifacts SHALL reflect the updated source

---

### Requirement: :NephBuild command for manual re-runs

A `:NephBuild` command SHALL be registered in `init.lua`. It SHALL run the build asynchronously and notify on completion.

#### Scenario: Successful manual build

- **WHEN** the user runs `:NephBuild`
- **THEN** Neovim SHALL NOT block during compilation
- **AND** a progress notification SHALL appear when the build starts
- **AND** a success notification SHALL appear when all tools are built
- **AND** the CLI symlink SHALL be (re)installed

#### Scenario: Build failure

- **WHEN** the build script exits non-zero
- **THEN** an ERROR notification SHALL appear with the first line of stderr
- **AND** existing `dist/` files SHALL be left unchanged (build output is atomic)

---

### Requirement: checkhealth reports stale build artifacts

`checkhealth neph` SHALL include a build-artifact staleness check that compares `dist/index.js` mtime against the newest `src/**/*.ts` mtime.

#### Scenario: Artifacts are current

- **WHEN** `dist/index.js` mtime ≥ newest source file mtime
- **THEN** the health check SHALL report OK

#### Scenario: Artifacts are stale

- **WHEN** any `src/*.ts` file is newer than `dist/index.js`
- **THEN** the health check SHALL report WARN with the message "neph CLI dist is stale — run :NephBuild"

#### Scenario: dist does not exist

- **WHEN** `tools/neph-cli/dist/index.js` does not exist
- **THEN** the health check SHALL report ERROR with the message "neph CLI not built — run :NephBuild"
