## Architecture

The gate and review CLI commands already call `status.set` / `status.unset` for per-agent state (`claude_active`, etc.). Adding `neph_connected` follows the exact same pattern — no new infrastructure needed.

```
Gate/Review CLI invocation
  ├─ Connect to Neovim socket
  ├─ status.set("neph_connected", "true")    ← NEW
  ├─ status.set("{agent}_active", "true")    ← existing
  ├─ ... run review flow ...
  ├─ status.unset("{agent}_active")          ← existing
  ├─ status.unset("neph_connected")          ← NEW
  └─ Close transport
```

## Implementation

### gate.ts Changes

In `runGate()`:
- After transport connection, before agent-specific status: `status.set("neph_connected", "true")`
- In `cleanup()`: `status.unset("neph_connected")` before `transport.close()`
- For cursor (post-write only path): same set/unset around the checktime call

### index.ts Changes (review command)

In the review command handler:
- After transport connection: `status.set("neph_connected", "true")`
- In cleanup: `status.unset("neph_connected")`

### Edge Cases

- **Multiple concurrent gates**: If two agents run gates simultaneously, the second `unset` would clear `neph_connected` while the first is still running. This is acceptable — the flag means "at least one neph operation happened recently", not "exactly N are active". For true reference counting, we'd need a counter, which is over-engineering.
- **Crash/timeout**: The 5-minute timeout in gate already calls cleanup, which will unset. If the CLI is killed (SIGKILL), Neovim retains the stale `vim.g` until next CursorHold cleanup or session end. This is fine — same behavior as existing `{agent}_active` flags.
- **No transport**: If socket discovery fails (no Neovim), skip entirely (fail-open, same as existing behavior).

## Testing

### TypeScript (gate.test.ts)
- Verify `neph_connected` is set before review.open RPC call
- Verify `neph_connected` is unset in cleanup
- Verify cursor post-write path sets and unsets `neph_connected`
- Verify no `neph_connected` call when transport is null

### TypeScript (commands.test.ts)
- Verify review command sets/unsets `neph_connected`

## Statusline Documentation

Users can consume these `vim.g` variables:

| Variable | Meaning |
|----------|---------|
| `vim.g.neph_connected` | A neph CLI operation is active (gate or review) |
| `vim.g.claude_active` | Claude agent is processing a tool call |
| `vim.g.gemini_active` | Gemini agent is processing a tool call |
| `vim.g.copilot_active` | Copilot agent is processing a tool call |
| `vim.g.cursor_active` | Cursor agent wrote a file |
| `vim.g.pi_active` | Pi session is live |
| `vim.g.pi_running` | Pi agent is processing a turn |

Example lualine component:

```lua
{
  function()
    if vim.g.neph_connected then return "neph" end
    return ""
  end,
  cond = function() return vim.g.neph_connected ~= nil end,
}
```
