## 1. Fix send_adapter

- [x] 1.1 Remove `vim.g.pi_active` guard from pi's `send_adapter` in `lua/neph/agents/pi.lua` — always set `vim.g.neph_pending_prompt` and return `true` when a pi terminal exists
- [x] 1.2 Add `neph_pending_prompt` cleanup to `session.close()` in `lua/neph/internal/session.lua` for pi agent (clear `vim.g.neph_pending_prompt = nil` when pi terminal is closed/killed)

## 2. Tests

- [x] 2.1 Add Lua unit test: pi send_adapter always returns true and sets `vim.g.neph_pending_prompt` (no `pi_active` dependency)
- [x] 2.2 Update existing pi.test.ts tests if any assert on `pi_active` gating behavior in the prompt poll flow
- [x] 2.3 Run full test suite (`task test`) to verify no regressions
