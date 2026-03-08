## Why

The prompt send pipeline has bugs (multiline input drops lines, `td.term:send()` may not use `chansend`, no placeholder escape syntax), agent integrations are tightly coupled (installing neph installs all agent adapters), and agents with programmatic APIs like pi's `sendUserMessage()` can't use them because everything goes through terminal paste.

## What Changes

- Fix multiline input to capture all lines, not just line 0
- Replace `td.term:send()` / WezTerm `send-text` with a send adapter layer that dispatches per-agent
- Add pi send adapter that uses `pi.sendUserMessage()` via neph RPC instead of terminal paste
- Use `vim.fn.chansend()` directly for the default terminal adapter
- Make `tools.install()` selective — only install tools for agents the user has enabled
- Add `config.agents` opt-in list (default: all available on PATH, preserving current behavior)
- Fix placeholder ergonomics: escape syntax (`\+token`), strip failed expansions, clean default template
- Add comprehensive tests for placeholder edge cases, send delivery, and adapter dispatch

## Capabilities

### New Capabilities
- `send-adapters`: Pluggable send layer that dispatches prompt delivery per-agent (terminal paste vs programmatic API)
- `selective-install`: `tools.install()` only sets up bridge/hooks for agents the user has opted into
- `placeholder-robustness`: Escape syntax, failed expansion handling, multiline input fix, clean defaults

### Modified Capabilities

## Impact

- `lua/neph/internal/session.lua` — send() rewritten to dispatch through adapter
- `lua/neph/internal/input.lua` — multiline confirm fix
- `lua/neph/internal/placeholders.lua` — escape syntax, failed expansion stripping
- `lua/neph/api.lua` — clean default templates
- `lua/neph/config.lua` — add `agents` key
- `lua/neph/tools.lua` — selective install based on config.agents
- `tools/pi/pi.ts` — add `sendUserMessage` bridge via neph RPC
- `tools/neph-cli/src/` — add `inject-prompt` command
- Tests: placeholder fuzz, send adapter unit tests, tools.install selectivity
