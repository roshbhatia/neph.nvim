## ADDED Requirements

### Requirement: Session lifecycle hooks

The system SHALL provide hooks that execute at session start and end.

#### Scenario: Execute session_start hook
- **WHEN** agent session is created
- **THEN** system SHALL invoke all registered `session_start` hooks
- **AND** provide session context (session_id, agent_name, protocol) as JSON on stdin
- **AND** wait for hook completion before proceeding

#### Scenario: Execute session_end hook
- **WHEN** agent session is terminated
- **THEN** system SHALL invoke all registered `session_end` hooks
- **AND** provide session context including duration and command count
- **AND** proceed with cleanup regardless of hook status

#### Scenario: Async session_end hooks
- **WHEN** session_end hooks are executing
- **THEN** system SHALL not block Neovim exit
- **AND** SHALL kill hooks after 5 second timeout

### Requirement: Tool execution hooks

The system SHALL provide hooks that execute before and after tool calls.

#### Scenario: Execute pre_tool hook
- **WHEN** tool is about to execute
- **THEN** system SHALL invoke all registered `pre_tool` hooks
- **AND** provide tool context (tool_name, tool_input) as JSON on stdin
- **AND** allow hook to modify tool input or cancel execution

#### Scenario: Hook modifies tool input
- **WHEN** pre_tool hook returns modified tool input on stdout
- **THEN** system SHALL use modified input for tool execution
- **AND** log the modification

#### Scenario: Hook cancels tool execution
- **WHEN** pre_tool hook exits with status code 2
- **THEN** system SHALL cancel tool execution
- **AND** return hook's stderr as error message to client

#### Scenario: Execute post_tool hook
- **WHEN** tool execution completes successfully
- **THEN** system SHALL invoke all registered `post_tool` hooks
- **AND** provide tool context including execution time and result

#### Scenario: Execute post_tool_failure hook
- **WHEN** tool execution fails
- **THEN** system SHALL invoke all registered `post_tool_failure` hooks
- **AND** provide error context including error message and stack trace

### Requirement: Hook registration

The system SHALL allow hooks to be registered via configuration or convention-based discovery.

#### Scenario: Register hook via config
- **WHEN** user provides config `hooks = { pre_tool = { command = "~/.neph/hooks/validate.sh" } }`
- **THEN** system SHALL register the hook
- **AND** execute it at pre_tool event

#### Scenario: Discover hooks by naming convention
- **WHEN** executable file exists at `~/.neph/hooks/pre_tool.sh`
- **THEN** system SHALL automatically register it as pre_tool hook

#### Scenario: Multiple hooks per event
- **WHEN** multiple hooks are registered for same event
- **THEN** system SHALL execute them in registration order
- **AND** pass output of each hook as input to next hook

### Requirement: Hook execution context

The system SHALL provide execution context via environment variables.

#### Scenario: Provide event context
- **WHEN** executing hook
- **THEN** system SHALL set `NEPH_HOOK_EVENT` to event name (session_start, pre_tool, etc.)

#### Scenario: Provide session context
- **WHEN** executing hook
- **THEN** system SHALL set `NEPH_SESSION_ID` to current session identifier
- **AND** set `NVIM_SOCKET` to Neovim socket path

#### Scenario: Provide tool context for tool hooks
- **WHEN** executing pre_tool or post_tool hook
- **THEN** system SHALL set `NEPH_TOOL_NAME` to tool being executed
- **AND** provide tool_input as JSON on stdin

### Requirement: Hook error handling

The system SHALL handle hook failures gracefully without blocking session operations.

#### Scenario: Continue on hook failure
- **WHEN** hook exits with non-zero status
- **THEN** system SHALL log the error
- **AND** continue with normal operation
- **EXCEPT** when hook exit code is 2 (explicit cancel signal)

#### Scenario: Timeout long-running hooks
- **WHEN** hook execution exceeds timeout (default 10 seconds)
- **THEN** system SHALL kill the hook process
- **AND** log timeout warning
- **AND** continue with normal operation
