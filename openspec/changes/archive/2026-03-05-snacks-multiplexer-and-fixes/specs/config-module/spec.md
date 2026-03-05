## MODIFIED Requirements

### Requirement: Dedicated config module
neph.nvim SHALL provide `lua/neph/config.lua` that defines the `defaults` table, the `neph.Config` type annotation, and the `neph.FileRefreshConfig` type annotation.

#### Scenario: Config module is importable
- **WHEN** `require("neph.config")` is called
- **THEN** it returns a table with at least a `defaults` field

#### Scenario: Defaults reflect snacks default and simplified file_refresh
- **WHEN** `require("neph.config").defaults` is accessed
- **THEN** it contains `keymaps = true`, `env = {}`, `file_refresh = { enable = true }`, `agents = nil`, and `multiplexer = "snacks"`
- **THEN** `file_refresh` does NOT contain `timer_interval` or `updatetime` keys

### Requirement: init.lua delegates to config module
`lua/neph/init.lua` SHALL import defaults from `lua/neph/config.lua` and SHALL NOT define its own `defaults` table or type annotations.

#### Scenario: init.lua is thin
- **WHEN** `lua/neph/init.lua` is read
- **THEN** it does not contain a `local defaults = {` table literal
- **THEN** it requires `neph.config` to obtain default values

## REMOVED Requirements

### Requirement: FileRefreshConfig exposes timer_interval and updatetime
**Reason**: These are internal implementation details with no user-tunable significance. Exposing them creates a false impression of configurability and clutters the public API.
**Migration**: Remove `timer_interval` and `updatetime` from any `file_refresh` table in `setup()` — they are silently ignored if passed (backward-compatible reads them as `opts.timer_interval or 1000`).
