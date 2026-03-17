---@type neph.AgentDef
return {
  name = "claude",
  label = "Claude",
  icon = "",
  cmd = "claude",
  args = { "--permission-mode", "plan" },
  type = "hook",
  ready_pattern = "^%s*>",
  ---@param _root string  neph.nvim plugin root path (unused — hooks point to cupcake)
  ---@return string[]
  launch_args_fn = function(_root)
    local settings = vim.json.encode({
      hooks = {
        PreToolUse = {
          {
            matcher = "Edit|Write",
            hooks = {
              {
                type = "command",
                command = "cupcake eval --harness claude",
              },
            },
          },
        },
      },
    })
    return { "--settings", settings }
  end,
}
