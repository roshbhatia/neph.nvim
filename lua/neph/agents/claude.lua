---@type neph.AgentDef
return {
  name = "claude",
  label = "Claude",
  icon = "",
  cmd = "claude",
  args = { "--permission-mode", "plan" },
  type = "hook",
  tools = {
    merges = {
      { src = "claude/settings.json", dst = "~/.claude/settings.json", key = "hooks" },
    },
  },
}
