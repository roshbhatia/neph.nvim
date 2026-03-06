local M = {}

function M.set(params)
  vim.g[params.name] = params.value
  return { ok = true }
end

function M.unset(params)
  vim.g[params.name] = nil
  return { ok = true }
end

return M
