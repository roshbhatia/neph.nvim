---@type neph.AgentDef
return {
  name = "claude",
  label = "Claude",
  icon = "  ",
  cmd = "claude",
  args = { "--permission-mode", "plan" },
  integration = {
    type = "hook",
    capabilities = { "review", "status", "checktime" },
  },
}
