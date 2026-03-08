---@mod neph.api.status Status management
---@brief [[
--- Manages vim.g global variables for statusline integration.
--- Used by the neph CLI to communicate agent state to Neovim.
---@brief ]]

local M = {}

---Set a vim.g global variable.
---@param params {name: string, value: any}
---@return {ok: boolean}
function M.set(params)
  if not params or not params.name or params.name == "" then
    return { ok = false, error = { code = "INVALID_PARAMS", message = "name is required" } }
  end
  vim.g[params.name] = params.value
  return { ok = true }
end

---Unset (clear) a vim.g global variable.
---@param params {name: string}
---@return {ok: boolean}
function M.unset(params)
  if not params or not params.name or params.name == "" then
    return { ok = false, error = { code = "INVALID_PARAMS", message = "name is required" } }
  end
  vim.g[params.name] = nil
  return { ok = true }
end

---Get a vim.g global variable.
---@param params {name: string}
---@return {ok: boolean, value: any}
function M.get(params)
  if not params or not params.name or params.name == "" then
    return { ok = false, error = { code = "INVALID_PARAMS", message = "name is required" } }
  end
  local value = vim.g[params.name]
  return { ok = true, value = value }
end

return M
