## ADDED Requirements

### Requirement: Edit tool exposes oldText and newText parameters
The edit tool override in `pi.ts` SHALL register with the schema from `createEditTool`, which contains `path`, `oldText`, and `newText` fields. It MUST NOT use the write tool schema (`path` + `content`).

#### Scenario: Agent sends oldText and newText
- **WHEN** the agent invokes the `edit` tool with `{ path, oldText, newText }`
- **THEN** the override receives `oldText` and `newText` as non-undefined strings

#### Scenario: oldText not found in file
- **WHEN** the edit tool is invoked and `oldText` is not present in the file on disk
- **THEN** the tool returns an error result containing "Edit failed" without calling preview

#### Scenario: Accepted edit applies correct replacement
- **WHEN** the edit tool is invoked, preview returns `{ decision: "accept", content: "replaced" }`, and `createEditTool.execute` is called
- **THEN** `createEditTool.execute` is called with the accepted content (not `createWriteTool.execute`)

#### Scenario: Rejected edit calls revert
- **WHEN** preview returns `{ decision: "reject" }` for an edit
- **THEN** `shim revert <path>` is called and the tool returns a rejection message

### Requirement: Edit tool delegates final write to createEditTool
The `edit` tool override SHALL call `createEditTool(cwd).execute` (not `createWriteTool`) when writing the final accepted content to disk.

#### Scenario: createEditTool execute is used on accept
- **WHEN** the user accepts the diff in the preview
- **THEN** the result returned to the agent matches the output of `createEditTool.execute`

#### Scenario: createWriteTool is not called for edit
- **WHEN** the edit tool override completes successfully
- **THEN** `createWriteTool` execute is NOT called as part of the edit flow
