---@type neph.AgentDef
return {
  name = "opencode",
  label = "OpenCode",
  icon = "  ",
  cmd = "opencode",
  args = { "--continue" },
  integration = {
    type = "extension",
    capabilities = { "review", "status" },
  },
}
