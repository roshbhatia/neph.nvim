---@type neph.AgentDef
return {
  name = "gemini",
  label = "Gemini",
  icon = "󰊭",
  cmd = "gemini",
  args = {},
  type = "extension",
  tools = {
    builds = {
      { dir = "gemini", src_dirs = { "src", "../lib" }, check = "dist/companion.js" },
    },
  },
}
