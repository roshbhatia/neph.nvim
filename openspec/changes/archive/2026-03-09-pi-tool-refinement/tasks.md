## 1. Refactor Tool Overrides

- [x] 1.1 Simplify the `edit` tool override in `tools/pi/pi.ts` by removing manual `readFileSync` and `oldText` matching.
- [x] 1.2 Standardize rejection messages in both `write` and `edit` tool overrides to be clear and SDK-compliant.
- [x] 1.3 Ensure the `createWriteTool` and `createEditTool` instances are correctly instantiated using the current `ctx.cwd`.

## 2. Testing & Validation

- [x] 2.1 Update `tools/pi/tests/pi.test.ts` to remove test cases that expect pre-review validation failures.
- [x] 2.2 Add or update tests to verify that rejection messages match the new standardized format.
- [x] 2.3 Verify that successful reviews still correctly delegate to the underlying tools.
