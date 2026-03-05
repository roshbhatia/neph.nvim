## ADDED Requirements

### Requirement: Executable script discovery

The system SHALL discover executable scripts in designated toolbox directories and register them as available tools.

#### Scenario: Discover scripts in user toolbox directory
- **WHEN** system initializes with default configuration
- **THEN** system SHALL scan `~/.neph/tools/` directory
- **AND** register all executable files as tools

#### Scenario: Discover scripts in multiple toolbox directories
- **WHEN** user sets `$NEPH_TOOLBOX=/project/.neph/tools:~/.neph/tools`
- **THEN** system SHALL scan directories left-to-right
- **AND** give precedence to earlier directories for duplicate tool names

#### Scenario: Skip non-executable files
- **WHEN** toolbox directory contains non-executable files
- **THEN** system SHALL skip those files
- **AND** only register files with execute permission

### Requirement: Tool description protocol

The system SHALL invoke scripts with `NEPH_ACTION=describe` to retrieve tool schema.

#### Scenario: Execute describe action
- **WHEN** system discovers new script `~/.neph/tools/custom_tool`
- **THEN** system SHALL execute script with environment variable `NEPH_ACTION=describe`
- **AND** capture stdout as JSON
- **AND** parse tool schema containing `name`, `description`, `inputSchema`

#### Scenario: Handle describe action failure
- **WHEN** script exits with non-zero status on describe action
- **THEN** system SHALL log error with script path and exit code
- **AND** SHALL NOT register the tool

#### Scenario: Cache tool descriptions
- **WHEN** tool description is successfully retrieved
- **THEN** system SHALL cache the schema
- **AND** SHALL NOT re-invoke describe action until cache is invalidated

### Requirement: Tool execution protocol

The system SHALL invoke scripts with `NEPH_ACTION=execute` and provide input via stdin.

#### Scenario: Execute tool with JSON input
- **WHEN** protocol adapter calls script with parameters `{path: "/tmp/test.txt"}`
- **THEN** system SHALL execute script with `NEPH_ACTION=execute`
- **AND** write JSON input to stdin
- **AND** capture stdout as tool result
- **AND** return stdout to protocol adapter

#### Scenario: Handle execution failure
- **WHEN** script exits with non-zero status during execution
- **THEN** system SHALL capture stderr
- **AND** return error to protocol adapter with stderr content

#### Scenario: Timeout long-running scripts
- **WHEN** script execution exceeds timeout (default 30 seconds)
- **THEN** system SHALL kill the script process
- **AND** return timeout error to protocol adapter

### Requirement: Environment variable context

The system SHALL provide execution context via environment variables.

#### Scenario: Provide session context
- **WHEN** executing script
- **THEN** system SHALL set environment variable `NEPH_SESSION_ID` to current session identifier
- **AND** set `NVIM_SOCKET` to Neovim socket path for reverse RPC

#### Scenario: Provide action context
- **WHEN** executing describe action
- **THEN** system SHALL set `NEPH_ACTION=describe`
- **WHEN** executing tool
- **THEN** system SHALL set `NEPH_ACTION=execute`

#### Scenario: Inherit user environment
- **WHEN** executing script
- **THEN** system SHALL inherit user's PATH and other environment variables
- **AND** prepend toolbox directory to PATH

### Requirement: Input schema validation

The system SHALL validate tool input against the declared inputSchema before execution.

#### Scenario: Validate required parameters
- **WHEN** tool declares `inputSchema` with required field `path`
- **AND** client invokes tool without `path` parameter
- **THEN** system SHALL reject invocation with validation error
- **AND** SHALL NOT execute the script

#### Scenario: Validate parameter types
- **WHEN** tool declares `path` parameter as type `string`
- **AND** client provides number value
- **THEN** system SHALL reject invocation with type error

#### Scenario: Allow optional parameters
- **WHEN** tool declares optional parameter
- **AND** client omits that parameter
- **THEN** system SHALL execute script with other parameters
- **AND** omit optional parameter from stdin JSON
