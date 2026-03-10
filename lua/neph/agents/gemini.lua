-- Review coverage: Companion sidecar's openDiff MCP tool routes writes through
-- NephClient.review(). The fs_watcher serves as safety net for any bypass.
---@type neph.AgentDef
return {
  name = "gemini",
  label = "Gemini",
  icon = "󰊭",
  cmd = "gemini",
  args = {},
  type = "extension",
  tools = {
    builds = {
      { dir = "gemini", src_dirs = { "src", "../lib" }, check = "dist/companion.js" },
    },
  },
}
