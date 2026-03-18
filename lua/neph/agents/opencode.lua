-- Review coverage: OpenCode has native Cupcake support.
-- `cupcake init --harness opencode` installs the Cupcake plugin.
-- All tool calls are routed through Cupcake policy evaluation.
---@type neph.AgentDef
return {
  name = "opencode",
  label = "OpenCode",
  icon = "",
  cmd = "opencode",
  args = {},
  type = "hook",
  integration_group = "harness",
}
