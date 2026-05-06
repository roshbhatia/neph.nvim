---@type neph.AgentDef
--- Claude Code agent operated through claudecode.nvim.
---
--- Requires the `coder/claudecode.nvim` plugin to be installed alongside
--- neph. claudecode handles the WebSocket/MCP transport, selection
--- broadcasting, and lockfile discovery; neph provides the picker, gate,
--- review queue, and history layer on top.
---
--- The claudecode openDiff MCP tool is overridden so diff approvals route
--- through neph's review queue instead of claudecode's native vimdiff
--- (gate=bypass auto-accepts; cycle <leader>jg to opt back in).
return {
  name = "claude",
  label = "Claude",
  icon = "",
  -- cmd is informational only when type=peer; the peer adapter does the launch.
  cmd = "claude",
  type = "peer",
  peer = {
    kind = "claudecode",
    override_diff = true,
  },
  -- No integration_group/tools: claudecode owns hooks and tool registration.
}
