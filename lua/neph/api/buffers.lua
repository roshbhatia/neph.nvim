---@mod neph.api.buffers Buffer management
---@brief [[
--- Provides buffer reload and tab management for the neph CLI bridge.
---@brief ]]

local M = {}

---Reload all buffers from disk (`:checktime`).
---@param params? table Unused, present for RPC dispatch consistency.
---@return {ok: boolean}
function M.checktime(_params)
  vim.cmd("checktime")
  return { ok = true }
end

---Close the current tab (`:tabclose`).
---@param params? table Unused, present for RPC dispatch consistency.
---@return {ok: boolean}
function M.close_tab(_params)
  if #vim.api.nvim_list_tabpages() > 1 then
    vim.cmd("tabclose")
  end
  return { ok = true }
end

return M
