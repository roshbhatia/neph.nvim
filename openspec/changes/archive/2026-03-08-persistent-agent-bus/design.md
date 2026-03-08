## Context

Extension agents (pi, amp, opencode) currently communicate with Neovim by spawning a neph CLI process for every operation. Pi's prompt delivery polls vim.g every 500ms, each poll spawning a full process (fork → connect socket → msgpack-rpc → exit). This architecture was expedient but doesn't scale — adding more extension agents multiplies the process-spawn overhead and the number of independent polling loops.

Neovim already runs a msgpack-rpc server on a Unix socket. The `neovim` npm package (already a dependency) can maintain persistent connections. The key insight: we're rebuilding a worse version of something Neovim already provides natively.

Three agent types exist today:
- **Terminal** (codex, crush, goose): plain terminal, no integration beyond chansend
- **Hook** (claude, gemini, cursor, copilot): terminal agent + neph gate intercepts stdout for review
- **Extension** (pi, amp, opencode): persistent process that needs bidirectional communication

## Goals / Non-Goals

**Goals:**
- Extension agents connect once and stay connected for the lifetime of their session
- Prompt delivery is push-based: Neovim notifies the agent instantly, no polling
- Status updates (pi_active, pi_running, etc.) flow over the same persistent connection
- A shared TypeScript client SDK makes it trivial for future extension agents to integrate
- Agent definitions become simpler: `type` field replaces `integration` + `send_adapter`
- Terminal and hook agent flows are completely untouched

**Non-Goals:**
- Changing how terminal agents send prompts (chansend stays)
- Changing how hook agents do review (neph gate stays)
- Supporting non-TypeScript agent SDKs (Python/Rust can come later, protocol is language-agnostic)
- Remote agent connections (TCP, auth — local Unix socket only)
- Event bus for arbitrary Lua-to-Lua events (this is specifically for external agent processes)

## Decisions

### 1. Use Neovim's native msgpack-rpc channel, not a custom server

Extension agents connect to `NVIM_SOCKET_PATH` using the `neovim` npm package. On connect, they call `executeLua('return require("neph.rpc").request("bus.register", {name = "pi"})')`. Neovim stores the RPC channel ID (available via `vim.api.nvim_get_chan_info()`). Prompts are pushed via `vim.rpcnotify(channel_id, "neph:prompt", {text, opts})`.

**Alternative considered:** Custom Unix socket server in Lua (vim.uv). Rejected — it would duplicate Neovim's existing server, require a second socket, and need its own protocol.

**Alternative considered:** WebSocket server. Rejected — adds a dependency, more complex than needed for local IPC, and Neovim can't speak WebSocket natively.

### 2. Channel ID comes from the RPC call itself

When an extension agent calls `bus.register("pi")`, the Lua side needs to know which RPC channel to notify. Neovim doesn't directly expose "the channel that made this RPC call" to Lua. However, extension agents can discover their own channel ID: after connecting, they call `nvim_get_api_info()` which returns `[channel_id, api_metadata]`. They pass this channel ID in the register call.

Flow:
```
agent connects → client.getApiInfo() → [channel_id, _]
agent calls register({name: "pi", channel: channel_id})
Lua stores: channels["pi"] = channel_id
```

### 3. Flat `type` field replaces `integration` + `send_adapter`

Today:
```lua
{
  name = "pi",
  integration = { type = "extension", capabilities = { "review", "status", "checktime" } },
  send_adapter = function(_td, text, opts) ... end,
}
```

After:
```lua
{
  name = "pi",
  type = "extension",
}
```

The `capabilities` array was never actually checked anywhere — it was documentation, not code. The `send_adapter` function becomes unnecessary because session.lua checks `type == "extension"` and routes through the bus automatically.

Agents without a `type` field are terminal agents (backward-compatible default).

### 4. Session.lua prompt routing by type

```lua
function M.send(termname, text, opts)
  local agent = agents.get_by_name(termname)
  if agent and agent.type == "extension" then
    local bus = require("neph.internal.bus")
    if bus.is_connected(termname) then
      bus.send_prompt(termname, text, opts)
      return
    end
    -- Extension not connected yet — fall through to terminal send
  end
  -- Default: chansend / wezterm CLI
  ...
end
```

This preserves the fallback behavior: if an extension agent isn't connected yet, prompts go to the terminal (which the agent also has). Once the agent registers, prompts go over the bus.

### 5. TypeScript client SDK (`tools/lib/neph-client.ts`)

Thin wrapper around `neovim` npm package:

```typescript
class NephClient {
  connect(socketPath?: string): Promise<void>  // defaults to NVIM_SOCKET_PATH
  register(agentName: string): Promise<void>
  onPrompt(callback: (text: string, opts: object) => void): void
  setStatus(name: string, value: string): Promise<void>
  unsetStatus(name: string): Promise<void>
  review(filePath: string, content: string): Promise<ReviewEnvelope>
  checktime(): Promise<void>
  disconnect(): void
}
```

Pi.ts becomes:
```typescript
const client = new NephClient();
await client.connect();
await client.register("pi");

client.onPrompt((text) => {
  pi.sendUserMessage(text);
});

// Status updates
await client.setStatus("pi_running", "true");

// Review (blocking RPC, returns user decision)
const result = await client.review(filePath, newContent);
```

### 6. Bus cleanup on channel close

Neovim fires `nvim_buf_detach` events but doesn't have a built-in "channel closed" callback for RPC channels. Instead, bus.lua uses a timer (1s interval) that checks registered channels with `pcall(vim.rpcnotify, channel_id, "neph:ping")`. If the notify fails, the channel is dead — clean up.

**Alternative considered:** `vim.api.nvim_create_autocmd("ChanClose", ...)` — this autocmd doesn't exist in Neovim. The `ChanInfo` event doesn't fire on close either.

**Alternative considered:** Agent sends an explicit "unregister" on shutdown. This is done (pi.ts calls disconnect), but the timer handles the crash case where the agent dies without cleanup.

### 7. neph-run.ts stays for gate and CLI one-offs

The spawn-per-operation `nephRun()` function is not deleted. It's still the right pattern for:
- `neph gate` (terminal agent file write interception)
- `neph review` (CLI-driven review, used by gate)
- One-off debugging commands from shell

Extension agents stop using it for hot-path communication but it remains available.

## Risks / Trade-offs

- **[Persistent connection requires reconnection logic]** → The current spawn-per-op model gets resilience "for free." A persistent connection needs retry logic. Mitigation: exponential backoff (100ms → 5s cap), auto-reconnect + re-register. The NephClient class handles this internally.

- **[Channel health check timer adds overhead]** → A 1s timer runs in Neovim to detect dead channels. Mitigation: the timer only iterates the registered channels table (expected: 0-3 entries). Cost is negligible.

- **[Breaking change for custom agents]** → Users who defined custom agents with `send_adapter` or `integration` must update. Mitigation: clear error messages in contract validation pointing to the new `type` field.

- **[Neovim restart kills all connections]** → If Neovim restarts, all extension agents lose their connection. Mitigation: NephClient reconnect logic handles this. The agent process stays alive and reconnects when the new Neovim socket appears.
