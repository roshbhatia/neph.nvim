## Why

Fifth e2e audit round uncovered window-validity crashes in the review UI, missing `await` on async handlers in the gate CLI, an event listener accumulation pattern in the transport layer, and a missed `.replace()` → `.replaceAll()` in pi.ts. These are crash/correctness risks during interactive review and gate hook flows.

## What Changes

- Guard all review UI keymaps against invalid windows (crash prevention during review)
- Add `finalized` checks in keymaps to prevent stale-state access after review completion
- Await async `handleResult()` calls in gate.ts notification and watcher callbacks
- Fix `.replace()` → `.replaceAll()` in pi.ts edit tool (consistency bug from round 3)
- Add listener cleanup to `SocketTransport.onNotification()` to prevent accumulation

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `review-ui`: Window validity guards in keymaps, finalized-state checks before accessing ui_state
- `neph-cli`: Await async handleResult in gate notification/watcher handlers, transport listener cleanup

## Impact

- `lua/neph/api/review/ui.lua` — keymap safety guards
- `tools/neph-cli/src/gate.ts` — await on handleResult calls
- `tools/neph-cli/src/transport.ts` — listener cleanup on close
- `tools/pi/pi.ts` — replaceAll fix
