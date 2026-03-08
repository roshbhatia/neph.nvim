---@type neph.AgentDef
return {
  name = "cursor",
  label = "Cursor",
  icon = "  ",
  cmd = "cursor-agent",
  args = {},
  integration = {
    type = "hook",
    capabilities = { "status", "checktime" },
  },
  tools = {
    symlinks = {
      { src = "cursor/hooks.json", dst = "~/.cursor/hooks.json" },
    },
  },
}
