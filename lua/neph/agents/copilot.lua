---@type neph.AgentDef
return {
  name = "copilot",
  label = "Copilot",
  icon = "",
  cmd = "copilot",
  args = { "--allow-all-paths" },
  integration = {
    type = "hook",
    capabilities = { "review", "status", "checktime" },
  },
}
