---@type neph.AgentDef
return {
  name = "amp",
  label = "Amp",
  icon = "󰫤",
  cmd = "amp",
  args = { "--ide" },
  type = "extension",
  tools = {
    symlinks = {
      { src = "amp/neph-plugin.ts", dst = "~/.config/amp/plugins/neph-plugin.ts" },
    },
  },
}
