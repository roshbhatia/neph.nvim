---@type neph.AgentDef
return {
  name = "opencode",
  label = "OpenCode",
  icon = "",
  cmd = "opencode",
  args = {},
  type = "hook",
  integration_group = "opencode_sse",
  -- Inject a free ephemeral port so opencode starts its HTTP server for SSE.
  -- session.lua discovers the port after launch via pgrep and subscribes.
  -- If port allocation fails, opencode runs without HTTP server (no integration).
  launch_args_fn = function(_root)
    local tcp = vim.uv.new_tcp()
    if not tcp then return {} end
    local ok = tcp:bind("127.0.0.1", 0)
    if not ok then
      tcp:close()
      return {}
    end
    local addr = tcp:getsockname()
    tcp:close()
    if not addr or not addr.port then return {} end
    return { "--port", tostring(addr.port) }
  end,
}
