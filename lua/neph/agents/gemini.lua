-- Review coverage: All writes/edits go through Cupcake's neph_review signal.
-- The gemini CLI's BeforeTool hook points to cupcake eval.
---@type neph.AgentDef
return {
  name = "gemini",
  label = "Gemini",
  icon = "󰊭",
  cmd = "gemini",
  args = {},
  type = "hook",
  ---@param _root string  neph.nvim plugin root path (unused — hooks point to cupcake)
  ---@return string[]
  launch_args_fn = function(_root)
    local settings = vim.json.encode({
      hooks = {
        BeforeTool = {
          {
            matcher = "write_file|edit_file|replace",
            hooks = {
              {
                type = "command",
                command = "cupcake eval --harness gemini",
              },
            },
          },
        },
      },
    })
    return { "--settings", settings }
  end,
}
