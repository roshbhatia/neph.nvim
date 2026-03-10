## ADDED Requirements

### Requirement: AgentDef supports dynamic launch args

`AgentDef` SHALL accept an optional `launch_args_fn` field — a function that takes the plugin root path (string) and returns a list of additional CLI arguments (string[]). When present, `session.lua:open()` SHALL call `launch_args_fn(plugin_root)` and append the returned arguments to the agent's static `args` before constructing the full command.

#### Scenario: Agent with launch_args_fn

- **WHEN** an agent defines `launch_args_fn = function(root) return {"--settings", '{"key":"val"}'} end`
- **AND** the agent's static `args` is `{"--permission-mode", "plan"}`
- **THEN** the resolved args at launch time SHALL be `{"--permission-mode", "plan", "--settings", '{"key":"val"}'}`

#### Scenario: Agent without launch_args_fn

- **WHEN** an agent does not define a `launch_args_fn` field
- **THEN** `session.lua:open()` SHALL use the static `args` unchanged
- **AND** no error SHALL occur

#### Scenario: launch_args_fn receives plugin root

- **WHEN** `session.lua:open()` calls `launch_args_fn`
- **THEN** the first argument SHALL be the absolute path to the neph.nvim plugin root (same value as `tools.get_root()`)

### Requirement: Claude agent uses runtime settings injection

The Claude agent definition SHALL use `launch_args_fn` to inject `--settings` with a JSON object containing hook definitions. The hook command SHALL use an absolute path to the neph-cli entry point (`node <root>/tools/neph-cli/dist/index.js gate --agent claude`) instead of relying on `neph` being on PATH.

#### Scenario: Claude launched with --settings flag

- **WHEN** a Claude terminal session is opened via `session.open("claude")`
- **THEN** the launch command SHALL include `--settings` followed by a JSON string
- **AND** the JSON SHALL contain a `hooks.PreToolUse` entry with matcher `Edit|Write`
- **AND** the hook command SHALL be `node <plugin_root>/tools/neph-cli/dist/index.js gate --agent claude`

#### Scenario: Claude settings merge additively with user config

- **WHEN** the user has their own hooks in `~/.claude/settings.json`
- **AND** Claude is launched with neph's `--settings` flag
- **THEN** both the user's hooks AND neph's hooks SHALL be active
- **AND** neph's hooks SHALL NOT replace or remove the user's hooks

#### Scenario: Claude agent has no tools.merges

- **WHEN** the Claude agent definition is loaded
- **THEN** it SHALL NOT have a `tools.merges` field
- **AND** no JSON merge into `~/.claude/settings.json` SHALL occur during tool installation

### Requirement: Session resolves dynamic args before backend dispatch

`session.lua:open()` SHALL resolve dynamic launch args by calling `launch_args_fn` (if present) and combining the result with static `args` before passing `agent_config` to the backend. The backend SHALL receive a fully resolved command with no deferred computation.

#### Scenario: Backend receives resolved args

- **WHEN** `session.lua:open()` dispatches to `backend.open()`
- **THEN** `agent_config.full_cmd` SHALL already contain all dynamic args
- **AND** the backend SHALL NOT need to call any agent functions

#### Scenario: Dynamic args resolution failure

- **WHEN** `launch_args_fn` raises an error
- **THEN** `session.lua:open()` SHALL log the error
- **AND** the agent SHALL still launch with only its static `args`
