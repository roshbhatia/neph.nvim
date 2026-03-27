---@mod neph.internal.gate_ui Gate state winbar indicator
---@brief [[
--- Sets a persistent winbar indicator on the focused window when gate
--- enters hold or bypass mode. Cleared when gate returns to normal.
---@brief ]]

local M = {}

local state = {
  win = nil,
  previous_winbar = nil,
}

local INDICATORS = {
  hold = "%#WarningMsg# ⏸ NEPH HOLD %*",
  bypass = "%#DiagnosticError# 󰈑 NEPH BYPASS %*",
}

---@param gate_state string  "hold" | "bypass"
---@param win? integer  window handle (defaults to current window)
function M.set(gate_state, win)
  local indicator = INDICATORS[gate_state]
  if not indicator then
    return
  end

  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  -- Save previous winbar for restoration
  state.win = win
  state.previous_winbar = vim.wo[win].winbar or ""

  local new_winbar
  if state.previous_winbar ~= "" then
    new_winbar = state.previous_winbar .. "  " .. indicator
  else
    new_winbar = indicator
  end

  pcall(function()
    vim.wo[win].winbar = new_winbar
  end)
end

--- Clear the gate indicator and restore the previous winbar value.
function M.clear()
  if not state.win then
    return
  end
  local win = state.win
  local prev = state.previous_winbar or ""
  state.win = nil
  state.previous_winbar = nil

  if vim.api.nvim_win_is_valid(win) then
    pcall(function()
      vim.wo[win].winbar = prev
    end)
  end
end

--- Reset all state (for testing).
function M._reset()
  state.win = nil
  state.previous_winbar = nil
end

return M
