local M = {}

function M.checktime()
  vim.cmd("checktime")
  return { ok = true }
end

function M.close_tab()
  vim.cmd("tabclose")
  return { ok = true }
end

return M
