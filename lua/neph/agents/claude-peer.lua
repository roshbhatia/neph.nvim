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
  -- "hook" integration group: review_provider=vimdiff with policy_engine=noop
  -- and formatter=noop. Gives neph's review UI for openDiff interception under
  -- gate=normal/hold without the cupcake policy layer (claudecode owns its own
  -- hook/tool surface; we're only here for the review UI).
  integration_group = "hook",
  -- Diff reviews use the full-screen vimdiff tab (granular per-hunk control).
  -- The floating popup is reserved for tool-approval / yes-no questionnaire
  -- flows surfaced via api.approval (vim.ui.select underneath).
}
