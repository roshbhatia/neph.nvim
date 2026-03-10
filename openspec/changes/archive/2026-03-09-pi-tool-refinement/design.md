## Context

The `pi` agent integration in `neph.nvim` overrides the `write` and `edit` tools to insert a Neovim-based `vimdiff` review step. Currently, the `edit` tool override manually checks if the file exists and if the search string (`oldText`) is present before triggering the review. This logic is redundant because the underlying `createEditTool` from the `@mariozechner/pi-coding-agent` SDK already performs these checks. Additionally, we want to ensure that if a review is rejected, the error message returned to the agent is professional and consistent with the SDK's internal expectations.

## Goals / Non-Goals

**Goals:**
- Simplify the `edit` tool override in `tools/pi/pi.ts` by removing redundant file reading and search string validation.
- Standardize rejection error messages for both `write` and `edit` tools.
- Ensure that the override remains a transparent drop-in that delegates as much logic as possible to the SDK's built-in tools.

**Non-Goals:**
- Changing the underlying RPC mechanism for reviews.
- Modifying the `pi-mono` SDK itself.

## Decisions

**1. Delegating Validation to SDK Tools:**
Instead of manually checking `readFileSync` and `includes(oldText)`, we will proceed directly to the `neph.review` step. If the user accepts the change in Neovim, we then call the original tool's `execute` method. If the original tool fails (e.g., because the search string didn't match), it will return its own native error message, which is what the agent expects anyway.
*Rationale:* Reduces code duplication and ensures that our override doesn't mask or accidentally alter the behavior of the native tools.

**2. Standardizing Rejection Messages:**
When `neph.review` returns a `reject` decision, we will return a result shape that matches the SDK's expected successful return type but with a text message indicating the user rejected the change.
*Rationale:* Ensures the agent receives a valid response structure and can decide how to proceed (e.g., trying a different approach).

## Risks / Trade-offs

- **[Risk] Late Validation**: By waiting until after the user finishes the review to find out `oldText` was missing, we might "waste" the user's time.
  - **Mitigation**: The `edit` tool is typically used by the agent when it's confident in the match. If the match fails, the user will see the diff in Neovim and can reject it themselves if they notice the error, or simply let the SDK tool return the match error afterwards.
- **[Risk] Diff Re-computation**: The `pi-mono` `edit` tool computes a diff. By showing our own `vimdiff`, we are technically providing a better UI, but we should make sure the final result returned to the agent (after delegation) contains the SDK's own diff metadata.
  - **Mitigation**: Since we call the original `execute` at the end, the agent gets the SDK's high-fidelity result including its own diffs.
