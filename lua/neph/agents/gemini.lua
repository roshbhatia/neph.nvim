---@type neph.AgentDef
return {
  name = "gemini",
  label = "Gemini",
  icon = " 󰊭 ",
  cmd = "gemini",
  args = {},
  integration = {
    type = "hook",
    capabilities = { "review", "status", "checktime" },
  },
}
