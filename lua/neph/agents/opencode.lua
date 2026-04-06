-- opencode agent definition.
--
-- Integration path selection:
--   opencode_sse  — opencode is running with --port; neph subscribes to the
--                   SSE stream and intercepts writes via the permission API.
--                   No Cupcake required.
--   harness       — fallback: Cupcake harness installed via
--                   `cupcake init --harness opencode`
--
-- The integration_group is set to "opencode_sse". When the SSE subscriber
-- cannot find a running opencode server (discover_port returns nil), session
-- open falls back to the harness group implicitly because the SSE path is
-- a no-op without a port.
---@type neph.AgentDef
return {
  name = "opencode",
  label = "OpenCode",
  icon = "",
  cmd = "opencode",
  args = {},
  type = "hook",
  integration_group = "opencode_sse",
  -- Inject --port when an existing opencode server is found, so neph can
  -- connect to its SSE stream.  Returns empty list when no server is found
  -- (opencode runs without HTTP server; Cupcake harness is the fallback).
  launch_args_fn = function(_root)
    local ok, sse = pcall(require, "neph.internal.opencode_sse")
    if not ok then
      return {}
    end
    local port = sse.discover_port()
    if port then
      return { "--port", tostring(port) }
    end
    return {}
  end,
}
