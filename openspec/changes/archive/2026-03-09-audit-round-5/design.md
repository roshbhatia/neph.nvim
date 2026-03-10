## Context

Audit round 5 found crash vectors in the review UI (keymaps accessing windows that may have been closed), silent promise losses in the gate CLI (async functions called without await), and a missed replaceAll fix in pi.ts.

## Goals / Non-Goals

**Goals:**
- Prevent crashes when review windows are closed while keymaps are still mapped
- Prevent stale-state access after review finalization (e.g., async vim.ui.input callback fires late)
- Ensure gate handleResult errors propagate rather than silently vanishing
- Fix pi.ts .replace() to .replaceAll() for edit correctness
- Clean up transport notification listeners on close

**Non-Goals:**
- Refactoring the review UI architecture
- Adding new review features
- Changing the transport API surface

## Decisions

1. **Window validity guard pattern**: Each keymap callback checks `vim.api.nvim_win_is_valid(ui_state.left_win)` before accessing cursor position. On invalid window, return early silently (the finalize path handles cleanup).

2. **Finalized guard in keymaps**: Each keymap checks `if finalized then return end` at the top. This prevents any stale-state access after `do_finalize()` has run.

3. **Void the promise in gate.ts**: The `onNotification` callback is synchronous (non-async), so we can't await directly. Instead, add `.catch()` to the `handleResult()` call to log errors to stderr rather than losing them. Same for the fs.watch callback.

4. **Transport listener cleanup**: Store registered listeners and remove them in `close()`. This prevents accumulation in long-lived transport instances (though current usage is short-lived per CLI invocation, this is defensive).

5. **pi.ts replaceAll**: Direct fix, same pattern as amp and opencode.

## Risks / Trade-offs

- Adding early-return guards to keymaps adds a small amount of code per keymap but prevents hard crashes — acceptable trade-off.
- The `.catch()` approach for handleResult is simpler than making the callback async, and avoids changing the onNotification callback signature.
