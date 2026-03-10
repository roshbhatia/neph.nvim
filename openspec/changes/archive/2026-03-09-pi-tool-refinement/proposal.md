## Why

The current `pi` tool overrides in `tools/pi/pi.ts` for `write` and `edit` duplicate logic that already exists in the native `pi-mono` tools (such as checking if a file exists or if `oldText` matches). This redundancy can lead to inconsistent error messages and maintenance overhead. Additionally, the error responses for rejected reviews should be standardized to match the expected return shapes of the `pi-mono` SDK to ensure the agent processes them correctly.

## What Changes

- Refactor `tools/pi/pi.ts` to remove redundant `readFileSync` and `includes(oldText)` checks in the `edit` tool override.
- Update error handling in `write` and `edit` overrides to return standard rejection messages that align with `pi-mono` conventions.
- Ensure the `neph.review` call remains the primary interception point for user approval before delegating to the underlying tool's `execute` method.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `pi-native-ui`: Refine the tool override implementation to be a more transparent drop-in replacement.

## Impact

- `tools/pi/pi.ts`
- Agent interaction reliability and consistency.
