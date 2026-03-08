---@type neph.AgentDef
return {
  name = "amp",
  label = "Amp",
  icon = " 󰫤 ",
  cmd = "amp",
  args = { "--ide" },
  integration = {
    type = "extension",
    capabilities = { "review", "status" },
  },
}
