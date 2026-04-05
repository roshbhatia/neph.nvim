---@type neph.AgentDef
return {
  name = "goose",
  label = "Goose",
  icon = "",
  cmd = "goose",
  args = {},
  type = "terminal",
  ready_pattern = "^%s*%(.-%)>",
  integration_group = "default",
}
