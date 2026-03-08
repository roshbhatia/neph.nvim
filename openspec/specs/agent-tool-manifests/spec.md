## ADDED Requirements

### Requirement: Declarative tool manifest on AgentDef
`AgentDef` SHALL accept an optional `tools` field containing declarative install specifications. The `tools` table MAY contain `symlinks`, `merges`, `builds`, and `files` sub-fields. All paths in `src` fields SHALL be relative to the `tools/` directory inside the plugin root.

#### Scenario: Agent with symlinks manifest
- **WHEN** an agent defines `tools = { symlinks = { { src = "pi/package.json", dst = "~/.pi/agent/extensions/nvim/package.json" } } }`
- **THEN** `tools.lua` SHALL create a symlink from `<plugin_root>/tools/pi/package.json` to the expanded `dst` path

#### Scenario: Agent with merges manifest
- **WHEN** an agent defines `tools = { merges = { { src = "claude/settings.json", dst = "~/.claude/settings.json", key = "hooks" } } }`
- **THEN** `tools.lua` SHALL additively merge the `hooks` key from the source JSON into the destination file

#### Scenario: Agent with builds manifest
- **WHEN** an agent defines `tools = { builds = { { dir = "pi", src_dirs = { "." }, check = "dist/pi.js" } } }`
- **THEN** `tools.lua` SHALL run `npm install && npm run build` in `<plugin_root>/tools/pi/` only if `dist/pi.js` is missing or source files are newer

#### Scenario: Agent with files manifest (create_only)
- **WHEN** an agent defines `tools = { files = { { dst = "~/.pi/index.ts", content = "export ...", mode = "create_only" } } }`
- **AND** the destination file does not exist
- **THEN** `tools.lua` SHALL create the file with the specified content

#### Scenario: Files with create_only does not overwrite
- **WHEN** an agent defines a file with `mode = "create_only"`
- **AND** the destination file already exists
- **THEN** `tools.lua` SHALL NOT overwrite the existing file

#### Scenario: Files with overwrite mode
- **WHEN** an agent defines a file with `mode = "overwrite"`
- **THEN** `tools.lua` SHALL always write the file regardless of whether it exists

#### Scenario: Agent with no tools field
- **WHEN** an agent defines no `tools` field
- **THEN** `tools.lua` SHALL skip that agent during installation without error

### Requirement: neph-cli is agent-independent
The neph-cli build and symlink SHALL remain in `tools.lua` as universal infrastructure not associated with any agent.

#### Scenario: neph-cli installed regardless of agents
- **WHEN** `tools.install_async()` runs
- **THEN** `tools/neph-cli/dist/index.js` SHALL be symlinked to `~/.local/bin/neph`
- **AND** this SHALL happen regardless of which agents are registered
