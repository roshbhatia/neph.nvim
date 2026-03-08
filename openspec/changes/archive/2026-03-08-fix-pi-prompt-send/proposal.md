## Why

Pi's `send_adapter` guards on `vim.g.pi_active`, which is set asynchronously by the pi extension's `session_start` event firing inside the pi process. When a user sends a prompt before pi finishes initializing, `vim.g.pi_active` is nil, the adapter returns `false`, and the prompt falls through to raw `chansend` — which pi never reads from stdin. The prompt is silently lost.

A secondary issue: `vim.g.neph_pending_prompt` has no acknowledgment mechanism, so rapid successive prompts can overwrite each other before pi's 500ms poll picks them up.

## What Changes

- Replace the `vim.g.pi_active` guard in pi's `send_adapter` with a readiness-wait mechanism that retries until pi signals it's ready (or times out)
- Add a prompt queue or acknowledgment handshake to prevent prompt loss from overwrite races on `vim.g.neph_pending_prompt`
- Ensure `ensure_active_and_send` waits for extension agent readiness, not just terminal existence

## Capabilities

### New Capabilities

- `extension-agent-send`: Reliable prompt delivery for extension-type agents (pi) including readiness gating and prompt queue/ack

### Modified Capabilities

## Impact

- `lua/neph/agents/pi.lua` — rewrite send_adapter to wait for readiness instead of failing immediately
- `lua/neph/internal/session.lua` — `ensure_active_and_send` may need an extension-agent readiness check in the retry loop
- `tools/pi/pi.ts` — may need prompt ack mechanism (clear `neph_pending_prompt` after consuming, or use a queue variable)
- Tests: pi send adapter tests, session send tests, pi.test.ts polling tests
