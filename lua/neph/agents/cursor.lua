---@type neph.AgentDef
return {
  name = "cursor",
  label = "Cursor",
  icon = "",
  cmd = "cursor-agent",
  args = {},
  type = "hook",
  tools = {
    symlinks = {
      { src = "cursor/hooks.json", dst = "~/.cursor/hooks.json" },
    },
  },
}
