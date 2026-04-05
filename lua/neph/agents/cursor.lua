-- Hook config is managed per-project by the neph CLI:
--   neph integration toggle cursor
-- This installs tools/cursor/hooks.json → $CWD/.cursor/hooks.json
-- and sets up Cupcake assets for the harness.
---@type neph.AgentDef
return {
  name = "cursor",
  label = "Cursor",
  icon = "",
  cmd = "cursor-agent",
  args = {},
  type = "hook",
  integration_group = "harness",
}
