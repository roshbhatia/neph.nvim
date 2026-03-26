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
  integration_group = "harness",
  tools = {
    { type = "symlink", src = "tools/pi/package.json", dst = "~/.pi/agent/extensions/nvim/package.json" },
    { type = "symlink", src = "tools/pi/dist", dst = "~/.pi/agent/extensions/nvim/dist" },
  },
}
