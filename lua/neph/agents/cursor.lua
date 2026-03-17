---@type neph.AgentDef
return {
  name = "cursor",
  label = "Cursor",
  icon = "",
  cmd = "cursor-agent",
  args = {},
  type = "hook",
  integration_group = "harness",
  tools = {
    symlinks = {
      { src = "cursor/hooks.json", dst = "~/.cursor/hooks.json" },
    },
  },
}
