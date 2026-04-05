---@mod neph.api.buffers Buffer management
---@brief [[
--- Provides buffer reload and tab management for the neph CLI bridge.
---@brief ]]

local M = {}

---Reload all buffers from disk (`:checktime`).
---@param params? table Unused, present for RPC dispatch consistency.
---@return {ok: boolean, error?: {code: string, message: string}}
function M.checktime(_params)
  local ok, err = pcall(vim.cmd, "checktime")
  if not ok then
    return { ok = false, error = { code = "CHECKTIME_FAILED", message = tostring(err) } }
  end
  return { ok = true }
end

---Close the current tab (`:tabclose`).
---@param params? table Unused, present for RPC dispatch consistency.
---@return {ok: boolean, error?: {code: string, message: string}}
function M.close_tab(_params)
  if #vim.api.nvim_list_tabpages() > 1 then
    local ok, err = pcall(vim.cmd, "tabclose")
    if not ok then
      return { ok = false, error = { code = "TABCLOSE_FAILED", message = tostring(err) } }
    end
  end
  return { ok = true }
end

return M
