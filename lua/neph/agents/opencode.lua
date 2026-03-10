---@type neph.AgentDef
return {
  name = "opencode",
  label = "OpenCode",
  icon = "",
  cmd = "opencode",
  args = { "--continue" },
  type = "extension",
  tools = {
    symlinks = {
      { src = "opencode/write.ts", dst = "~/.config/opencode/tools/write.ts" },
      { src = "opencode/edit.ts", dst = "~/.config/opencode/tools/edit.ts" },
      { src = "opencode/dist/opencode.js", dst = "~/.config/opencode/plugin/neph-companion.js" },
    },
    builds = {
      { dir = "opencode", src_dirs = { ".", "../lib" }, check = "dist/opencode.js" },
    },
  },
}
