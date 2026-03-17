---@mod neph.input Input prompt
---@brief [[
--- A thin wrapper around vim.ui.input that expands +token placeholders
--- before passing text to the callback.
---@brief ]]

local M = {}

local placeholders = require("neph.internal.placeholders")

--- Open an input prompt for *termname*.
---@param _termname   string
---@param agent_icon  string
---@param opts?       {action?:string, default?:string, on_confirm?:fun(text:string)}
function M.create_input(_termname, agent_icon, opts)
  opts = opts or {}
  local title = string.format("%s %s: ", agent_icon or "", opts.action or "Ask")

  -- Snapshot editor state before the input opens (cursor, selection, etc.)
  local initial_state = require("neph.internal.context").new()

  vim.ui.input({
    prompt = title,
    default = opts.default or "",
  }, function(value)
    if opts.on_confirm and value and value ~= "" then
      opts.on_confirm(placeholders.apply(value, initial_state))
    end
  end)
end

return M
