---@type neph.AgentDef
return {
  name = "gemini",
  label = "Gemini",
  icon = "󰊭",
  cmd = "gemini",
  args = {},
  type = "hook",
  tools = {
    merges = {
      { src = "gemini/settings.json", dst = "~/.gemini/settings.json", key = "hooks" },
    },
  },
}
