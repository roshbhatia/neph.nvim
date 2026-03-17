-- Amp Cupcake support is pending upstream.
-- For now, runs as terminal-only (no write interception).
-- When Cupcake ships amp harness, update to type="hook" with cupcake eval.
---@type neph.AgentDef
return {
  name = "amp",
  label = "Amp",
  icon = "󰫤",
  cmd = "amp",
  args = { "--ide" },
  env = { PLUGINS = "all" },
  type = "terminal",
}
