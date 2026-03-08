## Why

The gate parsers (`tools/neph-cli/src/gate.ts`) are the only part of neph where a third-party vendor changing their tool call JSON schema silently degrades the system. There are 4 hardcoded parsers (Claude, Copilot, Gemini, Cursor), each tightly coupled to exact field names (`file_path` vs `filepath`, `old_str` vs `old_string`, `toolArgs` as a JSON string vs object). The fail-safe means breakage is "review stops working" not data loss — but silent degradation is still bad. We should make the parsers data-driven so adding or updating agents doesn't require touching gate.ts logic.

## What Changes

- **Refactor**: Extract parser logic into a declarative schema per agent — a JSON/TS config that maps agent field names to GatePayload fields, rather than hand-coded functions
- **Add**: Debug logging when a parser returns null (fail-open) so silent degradation becomes visible in `/tmp/neph-debug.log`
- **Add**: Warn-on-unknown-fields heuristic — if stdin JSON has a `file_path`-like field but the parser returned null, log a warning suggesting the schema may have changed
- **Keep**: Existing fail-open behavior (exit 0 when parser returns null)
- **Keep**: Existing contract test fixtures and fuzz tests — they validate the declared schemas

## Capabilities

### New Capabilities
- `gate-parser-schemas`: Declarative schema definitions for agent tool call formats, replacing hardcoded parser functions

### Modified Capabilities
None — the gate command's external behavior (exit codes, fail-open, review flow) is unchanged.

## Impact

- `tools/neph-cli/src/gate.ts` — parser functions replaced with schema-driven normalizer
- `tools/neph-cli/tests/gate.test.ts` — update parser unit tests
- `tools/neph-cli/tests/gate.contract.test.ts` — tests should still pass (same fixtures, same outputs)
- `tools/neph-cli/tests/gate.fuzz.test.ts` — tests should still pass
- No Lua changes. No protocol changes. No breaking changes.
