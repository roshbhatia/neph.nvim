## ADDED Requirements

### Requirement: Declarative agent schema definitions
Each supported hook agent SHALL have a declarative schema object that defines how to extract `{ filePath, content }` from that agent's stdin JSON, including: tool name field path, tool input field path, file path field name, content field name, and optionally old/new text field names for edit operations.

#### Scenario: Claude schema maps tool_name, tool_input, file_path, content, old_str, new_str
- **WHEN** gate receives stdin JSON with `{ tool_name: "Write", tool_input: { file_path: "/a.ts", content: "new" } }`
- **THEN** the Claude schema SHALL extract `{ filePath: "/a.ts", content: "new" }`

#### Scenario: Gemini schema maps tool_name, tool_input, filepath (no underscore), content, old_string, new_string
- **WHEN** gate receives stdin JSON with `{ tool_name: "write_file", tool_input: { filepath: "/a.ts", content: "new" } }`
- **THEN** the Gemini schema SHALL extract `{ filePath: "/a.ts", content: "new" }`

#### Scenario: Copilot schema handles toolArgs as JSON string
- **WHEN** gate receives stdin JSON with `{ toolName: "edit", toolArgs: "{\"filepath\":\"/a.ts\",\"content\":\"new\"}" }`
- **THEN** the Copilot schema's preprocess step SHALL parse the JSON string before field extraction
- **THEN** the result SHALL be `{ filePath: "/a.ts", content: "new" }`

#### Scenario: Cursor schema extracts file_path only (post-write)
- **WHEN** gate receives stdin JSON with `{ file_path: "/a.ts" }`
- **THEN** the Cursor schema SHALL extract `{ filePath: "/a.ts", content: "" }`

### Requirement: Generic schema-driven parser
A single `parseWithSchema(schema, input)` function SHALL replace agent-specific parser functions. It SHALL use the schema's field mappings to extract tool name, file path, and content from any agent's stdin JSON.

#### Scenario: Write tool extraction via schema
- **WHEN** `parseWithSchema` receives a schema with `writeTools: ["Write"]` and input with matching tool name
- **THEN** it SHALL return `{ filePath, content }` using the schema's field mappings

#### Scenario: Edit tool extraction via schema with file reconstruction
- **WHEN** `parseWithSchema` receives a schema with `editTools: ["Edit"]` and input with matching tool name and old/new text fields
- **THEN** it SHALL read the existing file, apply the old→new replacement, and return the full reconstructed content

#### Scenario: Non-matching tool name returns null
- **WHEN** `parseWithSchema` receives input whose tool name is not in `writeTools` or `editTools`
- **THEN** it SHALL return null

#### Scenario: Preprocess hook runs before field extraction
- **WHEN** a schema defines a `preprocess` function
- **THEN** `parseWithSchema` SHALL call it on the raw input before extracting fields

### Requirement: Named parser exports preserved
The existing named exports (`parseClaude`, `parseCopilot`, `parseGemini`, `parseCursor`) SHALL continue to exist as public API, each delegating to `parseWithSchema` with the corresponding agent schema.

#### Scenario: parseClaude produces identical output to before
- **WHEN** `parseClaude` is called with any input that the old implementation accepted
- **THEN** it SHALL return the same `GatePayload` as the previous hardcoded implementation

#### Scenario: Existing contract test fixtures pass unchanged
- **WHEN** contract tests run against `tests/fixtures/*.json`
- **THEN** all existing assertions SHALL pass without modification

### Requirement: Debug logging on silent fail-open
When `parseWithSchema` returns null and the input JSON contains a field whose value looks like a file path (contains `/` or `\`), gate SHALL log a warning via the debug logger (`tools/lib/log.ts`) indicating the agent name and the path-like field found.

#### Scenario: Null return with path-like field logs warning
- **WHEN** `parseWithSchema` returns null for agent "claude"
- **AND** the input JSON contains a field with value "/tmp/foo.ts"
- **THEN** a debug log entry SHALL be written indicating the schema may need updating

#### Scenario: Null return without path-like fields does not log
- **WHEN** `parseWithSchema` returns null for a non-file-mutation tool call (e.g., `tool_name: "Read"`)
- **AND** the input JSON contains no path-like string values
- **THEN** no warning SHALL be logged

#### Scenario: Logging only active when NEPH_DEBUG=1
- **WHEN** `NEPH_DEBUG` is not set
- **THEN** no debug log entries SHALL be written regardless of parser results
