## 1. Schema Definitions

- [x] 1.1 Define `AgentSchema` interface and `SCHEMAS` record in `gate.ts` with schemas for claude, copilot, gemini, cursor
- [x] 1.2 Implement Copilot `preprocess` function (JSON-string `toolArgs` parsing)

## 2. Generic Parser

- [x] 2.1 Implement `parseWithSchema(schema, input)` function using field mappings, write/edit tool dispatch, and `reconstructEdit` for edits
- [x] 2.2 Wire `PARSERS` dict to use `parseWithSchema` with corresponding schema; keep named exports (`parseClaude`, etc.) as delegating wrappers

## 3. Debug Logging

- [x] 3.1 Add `tools/lib/log.ts` import to gate.ts and log warning when parser returns null but input contains path-like field values
- [x] 3.2 Add test for debug logging on null-return with path-like field

## 4. Validation

- [x] 4.1 Run existing contract tests (`gate.contract.test.ts`) — must pass with zero changes
- [x] 4.2 Run existing fuzz tests (`gate.fuzz.test.ts`) — must pass with zero changes
- [x] 4.3 Run existing unit tests (`gate.test.ts`) — update imports if needed, all assertions must pass
- [x] 4.4 Run `task tools:lint:neph` — must pass
