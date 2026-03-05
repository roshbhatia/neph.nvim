## ADDED Requirements

### Requirement: Dedicated config module
neph.nvim SHALL provide `lua/neph/config.lua` that defines the `defaults` table, the `neph.Config` type annotation, and the `neph.FileRefreshConfig` type annotation.

#### Scenario: Config module is importable
- **WHEN** `require("neph.config")` is called
- **THEN** it returns a table with at least `defaults` and `with(opts)` fields

#### Scenario: Defaults are unchanged from prior behavior
- **WHEN** `require("neph.config").defaults` is accessed
- **THEN** it contains `keymaps = true`, `env = {}`, `file_refresh = { enable = true, timer_interval = 1000, updatetime = 750 }`, `agents = nil`, and `multiplexer = nil`

### Requirement: init.lua delegates to config module
`lua/neph/init.lua` SHALL import defaults from `lua/neph/config.lua` and SHALL NOT define its own `defaults` table or type annotations.

#### Scenario: init.lua is thin
- **WHEN** `lua/neph/init.lua` is read
- **THEN** it does not contain a `local defaults = {` table literal
- **THEN** it requires `neph.config` to obtain default values
