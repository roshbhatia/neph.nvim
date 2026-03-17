-- Review coverage: Pi Cupcake harness intercepts write/edit tool_call events
-- and routes them through cupcake eval. Cupcake is required.
---@type neph.AgentDef
return {
  name = "pi",
  label = "Pi",
  icon = "󰏿",
  cmd = "pi",
  args = { "--continue" },
  type = "hook",
  tools = {
    symlinks = {
      { src = "pi/package.json", dst = "~/.pi/agent/extensions/nvim/package.json" },
      { src = "pi/dist", dst = "~/.pi/agent/extensions/nvim/dist" },
    },
    builds = {
      { dir = "pi", src_dirs = { "." }, check = "dist/cupcake-harness.js" },
    },
    files = {
      {
        dst = "~/.pi/agent/extensions/nvim/index.ts",
        content = 'export { default } from "./dist/cupcake-harness.js";',
        mode = "create_only",
      },
    },
  },
}
