## ADDED Requirements

### Requirement: Contract fixture files for each agent parser
Each gate parser (claude, copilot, gemini, cursor) SHALL have at least one fixture JSON file per supported tool call type (write, edit, create) stored in `tools/neph-cli/tests/fixtures/`.

#### Scenario: Claude write fixture
- **WHEN** the claude write fixture is parsed by `parseClaude`
- **THEN** it returns a valid `GatePayload` with the correct `filePath` and `content`

#### Scenario: Claude edit fixture
- **WHEN** the claude edit fixture is parsed by `parseClaude` with the target file on disk
- **THEN** it returns a `GatePayload` with the reconstructed full file content

#### Scenario: Copilot edit fixture
- **WHEN** the copilot edit fixture is parsed by `parseCopilot`
- **THEN** it returns a valid `GatePayload`

#### Scenario: Gemini write fixture
- **WHEN** the gemini write fixture is parsed by `parseGemini`
- **THEN** it returns a valid `GatePayload`

#### Scenario: Gemini edit fixture
- **WHEN** the gemini edit fixture is parsed by `parseGemini` with the target file on disk
- **THEN** it returns a `GatePayload` with reconstructed content

#### Scenario: Cursor post-write fixture
- **WHEN** the cursor fixture is parsed by `parseCursor`
- **THEN** it returns a `GatePayload` with the file path and empty content

### Requirement: Fixture tests fail on parser regression
If a parser change causes a fixture to return `null` or incorrect values, the corresponding test SHALL fail with a clear message identifying the fixture file and expected output.

#### Scenario: Parser change breaks fixture
- **WHEN** a developer changes `parseClaude` to expect a different field name
- **THEN** the fixture test fails with an assertion showing expected vs actual output
