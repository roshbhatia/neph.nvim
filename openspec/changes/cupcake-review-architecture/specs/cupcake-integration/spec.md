## ADDED Requirements

### Requirement: Cupcake is the sole integration layer

ALL agent hooks SHALL point to `cupcake eval`. No agent SHALL call neph-cli directly. No alternative integration path SHALL exist.

#### Scenario: Claude Code hook
- **WHEN** Claude Code fires a `PreToolUse` event for Write or Edit
- **THEN** the hook SHALL invoke `cupcake eval --harness claude`
- **AND** SHALL NOT invoke `neph-cli` directly

#### Scenario: Gemini CLI hook
- **WHEN** Gemini CLI fires a `BeforeTool` event for write_file, edit_file, or replace
- **THEN** the hook SHALL invoke `cupcake eval --harness gemini`
- **AND** SHALL NOT invoke `neph-cli` directly

#### Scenario: Pi extension
- **WHEN** Pi fires a `tool_call` event for write or edit
- **THEN** the Pi harness SHALL invoke `cupcake eval --harness pi`
- **AND** SHALL NOT invoke `neph-cli` directly

### Requirement: Cupcake signals call neph-cli

The `neph_review` Cupcake signal SHALL invoke `neph-cli review` as the editor interaction layer. Cupcake handles agent-specific normalization; neph-cli receives pre-normalized `{ path, content }`.

#### Scenario: Signal invocation for write tool
- **WHEN** Cupcake evaluates a write/edit tool and the review policy fires
- **THEN** it SHALL invoke the `neph_review` signal
- **AND** the signal SHALL pass `{ "path": "<abs_path>", "content": "<proposed>" }` on stdin to `neph-cli review`

#### Scenario: Signal returns accept
- **WHEN** `neph-cli review` returns `{ "decision": "accept", "content": "..." }`
- **THEN** the Rego policy SHALL emit an `allow` decision

#### Scenario: Signal returns partial
- **WHEN** `neph-cli review` returns `{ "decision": "partial", "content": "..." }`
- **THEN** the Rego policy SHALL emit a `modify` decision with `updated_input` containing the merged content

#### Scenario: Signal returns reject
- **WHEN** `neph-cli review` returns `{ "decision": "reject" }`
- **THEN** the Rego policy SHALL emit a `deny` decision

#### Scenario: Signal timeout
- **WHEN** the signal does not complete within 600 seconds
- **THEN** Cupcake SHALL terminate the signal
- **AND** the policy SHALL deny the action

### Requirement: Agent-specific normalization in Cupcake

Cupcake's harness layer SHALL normalize agent-specific tool JSON into the `{ path, content }` format before passing to the `neph_review` signal. Edit reconstruction (reading current file, applying old_str/new_str) SHALL happen in a preprocessing signal.

#### Scenario: Claude Write normalization
- **WHEN** Claude fires `{ tool_name: "Write", tool_input: { file_path, content } }`
- **THEN** Cupcake SHALL extract and pass `{ path: file_path, content }` to neph_review

#### Scenario: Claude Edit reconstruction
- **WHEN** Claude fires `{ tool_name: "Edit", tool_input: { file_path, old_string, new_string } }`
- **THEN** a reconstruction signal SHALL read the file, apply the replacement, and produce `{ path, content }`

#### Scenario: Gemini write_file normalization
- **WHEN** Gemini fires `{ tool_name: "write_file", tool_input: { filepath, content } }`
- **THEN** Cupcake SHALL extract and pass `{ path: filepath, content }` to neph_review

### Requirement: Cupcake initialization via neph setup

#### Scenario: Setup deploys policies and configures hooks
- **WHEN** `neph setup` runs
- **THEN** it SHALL verify Cupcake is installed (error if not)
- **AND** deploy Rego policies to `.cupcake/policies/neph/`
- **AND** configure `neph_review` signal in `.cupcake/rulebook.yml`
- **AND** configure agent hook configs to point to `cupcake eval`

### Requirement: Graceful behavior outside Neovim

When an agent runs outside Neovim (no `$NVIM` or `$NVIM_SOCKET_PATH` set), Cupcake SHALL still evaluate deterministic policies. The interactive review SHALL be skipped (fail-open) since there is no editor to review in.

#### Scenario: Agent outside Neovim — deterministic policies still enforce
- **WHEN** an agent runs in a terminal outside Neovim
- **AND** the agent proposes `rm -rf /`
- **THEN** Cupcake's dangerous_commands policy SHALL still deny the action
- **AND** the denial does NOT depend on Neovim being reachable

#### Scenario: Agent outside Neovim — review skipped
- **WHEN** an agent runs in a terminal outside Neovim
- **AND** the agent proposes a Write tool
- **AND** no deterministic policy blocks it
- **THEN** the `neph_review` signal SHALL invoke `neph-cli review`
- **AND** `neph-cli review` SHALL detect no Neovim socket
- **AND** SHALL return `{ "decision": "accept" }` (fail-open)
- **AND** SHALL log a warning to stderr

#### Scenario: Agent inside Neovim terminal — full review
- **WHEN** an agent runs inside Neovim's `:terminal`
- **AND** `$NVIM` is set
- **THEN** `neph-cli review` SHALL connect to Neovim via `$NVIM`
- **AND** the interactive vimdiff review SHALL open

### Requirement: Non-mutation tools pass through

#### Scenario: Read tool
- **WHEN** an agent proposes a Read, Glob, Grep, or Bash tool
- **AND** no blocking policy matches
- **THEN** Cupcake SHALL return `allow` without invoking the neph_review signal
