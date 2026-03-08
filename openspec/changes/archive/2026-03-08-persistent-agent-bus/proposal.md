## Why

Extension agents (pi, amp, opencode, and future integrations) communicate with Neovim by spawning a full neph CLI process for every operation — including a 500ms polling loop that spawns a process, connects a socket, does RPC, and exits, even when there's nothing to send. This is fragile, slow (6 hops per prompt delivery), and doesn't scale to N extension agents. Neovim already runs a perfectly good msgpack-rpc server on a Unix socket — extension agents should hold a persistent connection and receive prompts via push notifications instead of polling.

## What Changes

- **BREAKING**: Remove `send_adapter` field from agent definitions. Extension agents no longer define custom prompt routing — the bus handles it automatically based on agent type.
- **BREAKING**: Replace `integration = { type = "extension"|"hook", capabilities = {...} }` with a flat `type = "extension"|"hook"|nil` field on AgentDef. The nested table and capabilities array are unused ceremony.
- Add `lua/neph/internal/bus.lua` — channel registry that stores RPC channel IDs for connected extension agents. Provides `register(name)`, `send_prompt(name, text, opts)`, `on_disconnect(channel_id)`.
- Add `bus.register` and `bus.prompt` RPC methods to `rpc.lua` so extension agents can register and receive prompts over their persistent socket connection.
- Add `tools/lib/neph-client.ts` — shared TypeScript client SDK for extension agents. Connects to Neovim socket, registers with the bus, listens for `neph:prompt` notifications. Replaces the spawn-per-op pattern.
- Rewrite `tools/pi/pi.ts` to use `neph-client.ts` — delete the polling loop, delete the fire-and-forget neph queue, listen for prompt notifications instead.
- Update `session.lua` to route prompts for extension agents through the bus (via `vim.rpcnotify`) instead of through per-agent send_adapters.
- Update `contracts.lua` to validate the new `type` field and remove `send_adapter`/`integration` validation.
- Update all 10 agent definitions: remove `send_adapter` from pi, replace `integration` with `type` on pi/amp/opencode/claude/gemini/cursor/copilot.

## Capabilities

### New Capabilities
- `agent-bus`: Persistent-connection channel registry in Neovim that extension agents register with. Manages channel lifecycle, push-based prompt delivery via `vim.rpcnotify`, and automatic cleanup on disconnect.
- `agent-client-sdk`: Shared TypeScript client library (`tools/lib/neph-client.ts`) for extension agents to connect, register, receive prompts, set status, and request reviews over a persistent Neovim socket connection.

### Modified Capabilities
- `send-adapters`: **BREAKING** — Remove the `send_adapter` field. Prompt routing is now determined by agent `type`: extension agents go through the bus, terminal agents use chansend/wezterm CLI.
- `extension-agent-send`: **BREAKING** — Replace vim.g polling with push-based delivery via `vim.rpcnotify`. Remove `neph_pending_prompt` global entirely.
- `agent-submodules`: **BREAKING** — Replace `integration` field with flat `type` field. Remove `send_adapter` from pi agent definition.
- `constructor-injection`: **BREAKING** — Update contract validation to check `type` field instead of `send_adapter`/`integration`.

## Impact

- **Agent definitions**: All 10 agents updated (7 have integration field to migrate, 1 has send_adapter to remove)
- **Lua modules**: `bus.lua` (new), `session.lua`, `rpc.lua`, `contracts.lua`, `init.lua` modified
- **TypeScript**: `neph-client.ts` (new), `pi.ts` rewritten, `neph-run.ts` unchanged (still used for gate/CLI)
- **Tests**: Agent submodule tests, contracts tests, session tests, pi send_adapter tests all updated
- **neph CLI**: Unchanged — still used for terminal agent gate, debugging, one-off commands
- **User config**: Users passing custom agents with `send_adapter` or `integration` must update to `type`
