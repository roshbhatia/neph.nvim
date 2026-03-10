---@type neph.AgentDef
return {
  name = "claude",
  label = "Claude",
  icon = "",
  cmd = "claude",
  args = { "--permission-mode", "plan" },
  type = "hook",
  ---@param root string  neph.nvim plugin root path
  ---@return string[]
  launch_args_fn = function(root)
    local neph_bin = root .. "/tools/neph-cli/dist/index.js"
    local settings = vim.json.encode({
      hooks = {
        PreToolUse = {
          {
            matcher = "Edit|Write",
            hooks = {
              {
                type = "command",
                command = "node " .. neph_bin .. " gate --agent claude",
              },
            },
          },
        },
      },
    })
    return { "--settings", settings }
  end,
}
