## ADDED Requirements

### Requirement: Review-triggering Rego policy

The system SHALL provide a Rego policy that triggers the `neph_review` signal for file mutation tools and translates signal results into Cupcake decisions.

#### Scenario: Write tool triggers review
- **WHEN** `input.hook_event_name` is `"PreToolUse"` or `"BeforeTool"`
- **AND** `input.tool_name` matches a write/edit tool (Write, Edit, write_file, edit_file, replace)
- **AND** `input.signals.neph_review` is present
- **THEN** the policy SHALL evaluate the signal result to determine the decision

#### Scenario: Signal returns accept
- **WHEN** `input.signals.neph_review.decision == "accept"`
- **THEN** the policy SHALL emit an `allow` decision

#### Scenario: Signal returns partial with content
- **WHEN** `input.signals.neph_review.decision == "partial"`
- **AND** `input.signals.neph_review.content` is non-empty
- **THEN** the policy SHALL emit a `modify` decision with `updated_input` containing the merged content

#### Scenario: Signal returns reject
- **WHEN** `input.signals.neph_review.decision == "reject"`
- **THEN** the policy SHALL emit a `deny` decision with the signal's reason

#### Scenario: Signal data missing (timeout or error)
- **WHEN** the `neph_review` signal is not present in `input.signals`
- **AND** the tool is a write/edit mutation
- **THEN** the policy SHALL emit an `ask` decision prompting the user for manual approval

### Requirement: Protected paths policy

The system SHALL provide a Rego policy that blocks writes to configured protected paths.

#### Scenario: Write to protected path
- **WHEN** `input.tool_input.file_path` or `input.tool_input.filepath` matches a path in the protected paths list
- **THEN** the policy SHALL emit a `deny` decision with reason "Protected path: <path>"

#### Scenario: Write to unprotected path
- **WHEN** the file path does not match any protected path
- **THEN** this policy SHALL NOT emit any decision (allow by default)

### Requirement: Dangerous command blocking policy

The system SHALL provide a Rego policy that blocks dangerous shell commands.

#### Scenario: Block rm -rf
- **WHEN** `input.tool_name` is "Bash" or "run_shell_command"
- **AND** `input.tool_input.command` contains "rm -rf"
- **THEN** the policy SHALL emit a `deny` decision

#### Scenario: Block force push
- **WHEN** the command contains "git push --force" or "git push -f"
- **THEN** the policy SHALL emit a `deny` decision

#### Scenario: Block no-verify
- **WHEN** the command contains "--no-verify"
- **THEN** the policy SHALL emit a `deny` decision

### Requirement: Policy routing metadata

All neph Rego policies SHALL include routing metadata to enable Cupcake's O(1) policy lookup.

#### Scenario: Review policy routing
- **WHEN** the review-triggering policy is loaded
- **THEN** its metadata SHALL declare `required_events: ["PreToolUse", "BeforeTool"]`
- **AND** `required_tools: ["Write", "Edit", "write_file", "edit_file", "replace"]`
- **AND** `required_signals: ["neph_review"]`

#### Scenario: Dangerous command policy routing
- **WHEN** the dangerous command policy is loaded
- **THEN** its metadata SHALL declare `required_events: ["PreToolUse", "BeforeTool"]`
- **AND** `required_tools: ["Bash", "run_shell_command"]`
