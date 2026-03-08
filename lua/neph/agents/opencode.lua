---@type neph.AgentDef
return {
  name = "opencode",
  label = "OpenCode",
  icon = "",
  cmd = "opencode",
  args = { "--continue" },
  integration = {
    type = "extension",
    capabilities = { "review", "status" },
  },
  tools = {
    symlinks = {
      { src = "opencode/write.ts", dst = "~/.config/opencode/tools/write.ts" },
      { src = "opencode/edit.ts", dst = "~/.config/opencode/tools/edit.ts" },
    },
  },
}
