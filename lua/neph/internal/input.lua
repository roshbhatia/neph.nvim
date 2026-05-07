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
---@param opts?       {action?:string, default?:string, selection_marks?:table, on_confirm?:fun(text:string)}
function M.create_input(_termname, agent_icon, opts)
  opts = opts or {}
  local title = string.format("%s %s: ", agent_icon or "", opts.action or "Ask")

  -- Snapshot editor state before the input opens. When the caller passed
  -- explicit selection_marks (set by `<leader>ja` / `<leader>jc` from a
  -- recent visual selection), prefer the marks-based capture — it doesn't
  -- depend on `vim.fn.mode()` which is unreliable in keymap callbacks.
  local context = require("neph.internal.context")
  local initial_state
  if opts.selection_marks then
    initial_state = context.from_marks(vim.api.nvim_get_current_buf(), opts.selection_marks)
  else
    initial_state = context.new()
  end

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
