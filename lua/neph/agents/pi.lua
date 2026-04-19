---@type neph.AgentDef
return {
  name = "pi",
  label = "Pi",
  icon = "󰏿",
  cmd = "pi",
  args = { "--continue" },
  type = "hook",
  integration_group = "harness",
  -- Load the neph RPC extension at launch via -e so it fires only when pi is
  -- started through neph (not global install).  Falls back gracefully when the
  -- built artifact is missing (run :NephInstall to rebuild).
  launch_args_fn = function(root)
    local ext_path = root .. "/tools/pi/dist/pi.js"
    if vim.fn.filereadable(ext_path) == 1 then
      return { "-e", ext_path }
    end
    return {}
  end,
}
