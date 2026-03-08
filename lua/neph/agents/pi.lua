---@type neph.AgentDef
return {
  name = "pi",
  label = "Pi",
  icon = "",
  cmd = "pi",
  args = { "--continue" },
  type = "extension",
  tools = {
    symlinks = {
      { src = "pi/package.json", dst = "~/.pi/agent/extensions/nvim/package.json" },
      { src = "pi/dist", dst = "~/.pi/agent/extensions/nvim/dist" },
    },
    builds = {
      { dir = "pi", src_dirs = { ".", "../lib" }, check = "dist/pi.js" },
    },
    files = {
      {
        dst = "~/.pi/agent/extensions/nvim/index.ts",
        content = 'export { default } from "./dist/pi.js";',
        mode = "create_only",
      },
    },
  },
}
