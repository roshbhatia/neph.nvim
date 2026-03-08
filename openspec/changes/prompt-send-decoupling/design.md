## Context

Prompts are sent to agents via two paths: native snacks terminal (`td.term:send()`) and WezTerm CLI (`wezterm cli send-text`). Both are terminal paste — text goes into the pty. This causes issues: long text wraps/splits at pty column width, special characters can be misinterpreted, and agents with programmatic input APIs (pi's `sendUserMessage()`) can't use them.

The input system captures only line 0 of multiline input, placeholder expansion has no escape syntax and leaves raw tokens on failed expansion, and `tools.install()` installs all agent adapters regardless of what the user actually uses.

## Goals / Non-Goals

**Goals:**
- Reliable prompt delivery: text arrives intact regardless of length, encoding, or terminal width
- Pi uses `sendUserMessage()` instead of terminal paste when its extension is active
- Users only install tooling for agents they use
- Placeholder expansion is robust: escapable, graceful on failure, correct with special chars
- All changes have test coverage

**Non-Goals:**
- Separate agent adapter packages (too much complexity for now)
- Programmatic send for Claude/Copilot/Gemini (they don't expose APIs for this)
- Changing the review system (already works well)
- Supporting agents not in the current registry

## Decisions

### 1. Send adapter as a simple function table, not a class hierarchy

**Choice:** Each agent can optionally specify a `send_adapter` — a table with a `send(text, opts)` function. Session.send() checks for a custom adapter, falls back to a default.

**Why:** Only pi needs a custom adapter right now. A function table is the minimum viable abstraction. If more agents need custom adapters later, the pattern is established.

**Alternative:** Adapter registry with formal registration API. Rejected — premature for one custom adapter.

### 2. Pi prompt injection via vim.g polling, not RPC server

**Choice:** Neph Lua side sets `vim.g.neph_pending_prompt = text`. The pi extension polls for this value (it already polls the neph CLI for status) and calls `pi.sendUserMessage()`.

**Why:** Pi extension already communicates with neovim via `neph` CLI calls that set/unset vim.g globals. Adding another vim.g is consistent. An RPC server would require pi to listen on a socket, adding complexity.

**Flow:**
```
Lua session.send("pi", text)
  → vim.g.neph_pending_prompt = text
  → pi extension detects (via neph CLI polling or input event)
  → pi.sendUserMessage(text)
  → vim.g.neph_pending_prompt = nil
```

**Alternative:** Use pi's `input` event to intercept terminal input and transform it. Rejected because it still requires text to go through the pty first.

### 3. Default terminal adapter uses chansend directly

**Choice:** Replace `td.term:send(text)` with `vim.fn.chansend(vim.b[td.buf].terminal_job_id, text)`.

**Why:** `td.term:send()` relies on Snacks terminal implementing a send method, which may not exist or may not use chansend internally. Using chansend directly removes the dependency on Snacks internals and guarantees raw byte delivery to the pty.

### 4. Selective install via config.agents allowlist

**Choice:** `config.agents` is an optional list of agent names. When present, `tools.install()` and `agents.get_all()` filter to only those agents. When absent, all agents on PATH are active (backward compatible).

**Why:** Simple opt-in model. Users who only use claude+pi don't get copilot hooks installed. The filtering happens at the agent registry level so it's consistent everywhere.

### 5. Placeholder escape with backslash, strip on failure

**Choice:** `\+token` → literal `+token`. Failed expansions (nil provider result) → remove the `+token` text and collapse surrounding whitespace.

**Why:** Backslash escape is the universal convention. Stripping failed tokens is better than leaving raw `+cursor` in the prompt — agents don't know what `+cursor` means.

## Risks / Trade-offs

- [Pi polling latency] vim.g polling in the pi extension adds a small delay vs terminal paste. Mitigation: poll interval is already fast for status updates; prompt injection is infrequent.
- [chansend behavior difference] Switching from `td.term:send()` to `chansend` could change behavior if Snacks was doing preprocessing. Mitigation: chansend is what Snacks should be using anyway; test with all backends.
- [Stripping failed tokens changes existing behavior] Currently `+cursor` stays as-is if it can't resolve. Stripping it changes what the agent sees. Mitigation: raw `+cursor` in a prompt is never useful to an agent, so stripping is strictly better.
- [config.agents breaks existing setups] Users who rely on all agents being auto-discovered won't be affected (default is all-on-PATH). Only users who set the key see different behavior.
