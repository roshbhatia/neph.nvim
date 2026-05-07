## MODIFIED Requirements

### Requirement: Peer agents default to popup review style

Peer agents (`type = "peer"`) SHALL default to `review_style = "popup"` so that pre-write review approvals match the lightweight feel of the underlying peer plugins. Other agent types (`hook`, `terminal`) keep the existing `tab` default. Users MAY override either default via `setup({ review = { style = "tab" | "popup" } })` (global) or per-agent on the AgentDef.

#### Scenario: claude-peer agent definition declares popup style

- **WHEN** `lua/neph/agents/claude-peer.lua` is required
- **THEN** the returned AgentDef SHALL include `review_style = "popup"`

#### Scenario: opencode-peer agent definition declares popup style

- **WHEN** `lua/neph/agents/opencode-peer.lua` is required
- **THEN** the returned AgentDef SHALL include `review_style = "popup"`

#### Scenario: User can override peer-agent default to tab

- **GIVEN** the user calls `setup({ review = { style = "tab" } })`
- **WHEN** a claude-peer pre-write review is opened
- **THEN** the vimdiff tab UI SHALL be shown (overriding the per-agent `popup` default)

### Requirement: claudecode peer adapter supports external (wezterm) terminal provider

The `lua/neph/peers/claudecode.lua` adapter SHALL expose a public helper `M.wezterm_pane_cmd(cmd_string, env_table)` that returns argv for spawning the claude CLI in a wezterm split-pane while capturing the resulting pane_id. When the helper is wired into claudecode's `terminal.provider_opts.external_terminal_cmd`, the peer adapter SHALL track the pane_id internally and use it for `send` / `is_visible` / `focus` / `kill` operations. When no pane_id is tracked (e.g., user is on the snacks/native provider), all operations SHALL fall back to the existing bufnr-based paths so non-wezterm users are unaffected.

#### Scenario: wezterm_pane_cmd returns the expected argv shape

- **WHEN** `M.wezterm_pane_cmd("claude --foo", {})` is called
- **THEN** the return value SHALL be a table of the form `{ "sh", "-c", <command-string> }`
- **AND** the command-string SHALL contain `wezterm cli split-pane --right --cwd <cwd>`
- **AND** SHALL pass the `cmd_string` argument to the inner shell via `sh -c`
- **AND** SHALL redirect stdout to a tempfile so the pane_id (which `split-pane` prints) can be captured

#### Scenario: Pane_id captured asynchronously

- **GIVEN** `M.wezterm_pane_cmd` was called and the wezterm CLI spawned the pane
- **WHEN** ~200 ms have elapsed (the configured `vim.defer_fn` delay)
- **THEN** the adapter SHALL have read the pane_id from the tempfile
- **AND** SHALL have removed the tempfile

#### Scenario: M.send dispatches via wezterm cli when pane_id is present

- **GIVEN** the adapter has a tracked `pane_id` (e.g., from a recent `wezterm_pane_cmd` invocation)
- **WHEN** `M.send(_td, "hello", { submit = true })` is called
- **THEN** the adapter SHALL invoke `wezterm cli send-text --pane-id <pane_id> --no-paste "hello\r"`
- **AND** SHALL NOT attempt to read a bufnr from `claudecode.terminal.get_active_terminal_bufnr()`

#### Scenario: M.send falls back to chansend when no pane_id

- **GIVEN** the adapter has no tracked pane_id (snacks/native provider or initial state)
- **WHEN** `M.send(_td, "hello", { submit = true })` is called
- **THEN** the adapter SHALL call `claudecode.terminal.get_active_terminal_bufnr()`
- **AND** if the bufnr is valid, SHALL chansend `"hello\n"` to the buffer's `terminal_job_id`

#### Scenario: M.kill kills the wezterm pane and clears state

- **GIVEN** the adapter has a tracked pane_id
- **WHEN** `M.kill(_td)` is called
- **THEN** the adapter SHALL invoke `wezterm cli kill-pane --pane-id <pane_id>`
- **AND** SHALL set the internal pane_id to nil
- **AND** SHALL also call `claudecode.stop` to halt the MCP server

#### Scenario: VimLeavePre cleans up the pane

- **GIVEN** the adapter has a tracked pane_id
- **WHEN** Neovim exits (`VimLeavePre` fires)
- **THEN** the adapter's autocmd in augroup `NephClaudecodeWezterm` SHALL invoke `wezterm cli kill-pane --pane-id <pane_id>`
- **AND** the pane_id SHALL NOT remain orphaned after nvim exit

#### Scenario: M.is_visible uses wezterm cli list when pane_id is owned

- **GIVEN** the adapter has a tracked pane_id
- **WHEN** `M.is_visible(_td)` is called
- **THEN** the adapter SHALL invoke `wezterm cli list --format json`, parse the result, and return `true` iff the tracked pane_id appears in the list
- **AND** SHALL NOT depend on any nvim-side bufnr

### Requirement: Peer adapter visual-selection awareness

When the user invokes `<leader>ja` or `<leader>jc` from visual mode, `api.ask` and `api.comment` SHALL capture the visual selection from the `'<` and `'>` marks (not from `vim.fn.mode()`, which has already transitioned to normal by the time the keymap callback fires) and SHALL prefill the input prompt with `"+selection "` so the placeholder system can expand the selected text.

#### Scenario: Visual mode marks captured

- **GIVEN** the user selects three lines in normal-mode buffer `foo.lua`
- **AND** presses `<leader>ja`
- **WHEN** the keymap callback runs (in normal mode, after the visual transition)
- **THEN** `api.ask` SHALL read marks `'<` and `'>` (both non-zero, bounding the selection)
- **AND** SHALL pass `selection_marks = {from, to, kind}` through to `input_for_active`
- **AND** the prompt default SHALL be `"+selection "`
- **AND** on submit, `placeholders.apply` SHALL expand `+selection` to the selected text via `context.from_marks(buf, marks)`

#### Scenario: Normal mode (no marks) falls back to cursor

- **GIVEN** the user is in normal mode with no recent visual selection (marks `'<` and `'>` are unset, both at line 0)
- **WHEN** `<leader>ja` fires
- **THEN** `api.ask` SHALL detect unset marks
- **AND** the prompt default SHALL be `"+cursor "`
