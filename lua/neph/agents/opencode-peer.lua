---@type neph.AgentDef
--- OpenCode agent operated through opencode.nvim.
---
--- Requires the `nickjvandyke/opencode.nvim` plugin to be installed
--- alongside neph. opencode.nvim manages the HTTP/SSE transport, prompt
--- input UI, and context system; neph provides the picker, gate, review
--- queue, and history layer on top.
return {
  name = "opencode-peer",
  label = "OpenCode (peer)",
  icon = "",
  cmd = "opencode",
  type = "peer",
  peer = {
    kind = "opencode",
  },
}
