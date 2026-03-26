-- Amp review interception is handled by the neph-plugin.ts amp plugin (tool.call hook).
-- The plugin auto-connects via NVIM_SOCKET_PATH forwarded by the backend.
-- tools: neph-plugin.ts symlinked to ~/.config/amp/plugins/neph-plugin.ts
---@type neph.AgentDef
return {
  name = "amp",
  label = "Amp",
  icon = "󰫤",
  cmd = "amp",
  args = { "--ide" },
  env = { PLUGINS = "all" },
  type = "terminal",
  integration_group = "default",
  tools = {
    { type = "symlink", src = "tools/amp/neph-plugin.ts", dst = "~/.config/amp/plugins/neph-plugin.ts" },
  },
}
