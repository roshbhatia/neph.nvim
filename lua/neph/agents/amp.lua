---@type neph.AgentDef
return {
  name = "amp",
  label = "Amp",
  icon = "󰫤",
  cmd = "amp",
  args = { "--ide" },
  env = { PLUGINS = "all" },
  type = "extension",
  tools = {
    symlinks = {
      { src = "amp/dist/amp.js", dst = "~/.config/amp/plugins/neph-companion.js" },
    },
    builds = {
      { dir = "amp", src_dirs = { ".", "../lib" }, check = "dist/amp.js" },
    },
  },
}
