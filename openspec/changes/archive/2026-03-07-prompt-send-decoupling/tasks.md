## 1. Placeholder robustness

- [x] 1.1 Fix multiline input: change `input.lua` confirm to read all buffer lines and join with `\n`
- [x] 1.2 Add backslash escape syntax to `placeholders.apply()`: `\+token` → literal `+token`
- [x] 1.3 Strip failed expansions (nil provider result) and collapse surrounding whitespace
- [x] 1.4 Clean default templates in `api.lua`: `"+cursor "` (no leading space, no trailing colon)
- [x] 1.5 Add placeholder tests: multiline, escape syntax, failed expansion stripping, regex metacharacters in values, repeated tokens, pipe fallback, unicode in paths

## 2. Send adapter layer

- [x] 2.1 Replace `td.term:send()` in `session.lua` with `vim.fn.chansend(vim.b[td.buf].terminal_job_id, text)` for the native backend
- [x] 2.2 Add send adapter dispatch: check agent for custom `send_adapter`, fall back to default chansend/wezterm
- [x] 2.3 Add pi send adapter in Lua: sets `vim.g.neph_pending_prompt` when `vim.g.pi_active` is truthy, falls back to terminal otherwise
- [x] 2.4 Update pi extension (`pi.ts`) to poll for `vim.g.neph_pending_prompt` and call `pi.sendUserMessage()` when found
- [x] 2.5 Add `get` command to neph CLI + `status.get` RPC handler to read `vim.g` variables
- [x] 2.6 Add send adapter tests: `get` command routing, prompt polling delivery, no-op when empty, poll stops on shutdown

## 3. Selective install

- [x] 3.1 Add `enabled_agents` string[] allowlist to `neph.Config` in `config.lua`
- [x] 3.2 Update `agents.get_all()` and `agents.get_by_name()` to filter by `config.enabled_agents` when set
- [x] 3.3 Make `tools.install()` selective: only install hooks/extensions/configs for enabled agents (neph CLI always installed)
- [x] 3.4 Add selective install tests: agent filtering, empty allowlist, nil allowlist backward compat

## 4. Integration verification

- [x] 4.1 Run full test suite: 230 vitest + 84 plenary = 314 tests, all passing
- [x] 4.2 E2E code review verified both paths correct; live manual test deferred to user
