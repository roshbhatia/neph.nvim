---@type neph.AgentDef
return {
  name = "claude",
  label = "Claude",
  icon = "",
  cmd = "claude",
  args = { "--permission-mode", "plan" },
  integration = {
    type = "hook",
    capabilities = { "review", "status", "checktime" },
  },
  tools = {
    merges = {
      { src = "claude/settings.json", dst = "~/.claude/settings.json", key = "hooks" },
    },
  },
}
