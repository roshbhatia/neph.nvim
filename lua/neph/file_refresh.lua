---@mod neph.file_refresh External file-change detection
---@brief [[
--- Watches for files modified by external AI agents and calls :checktime
--- so Neovim reloads them automatically.
---@brief ]]

local M = {}

---@type userdata|nil
local timer = nil

---@param config neph.Config
function M.setup(config)
  local cfg = (config or {}).file_refresh or {}
  if not cfg.enable then return end

  local augroup = vim.api.nvim_create_augroup("NephFileRefresh", { clear = true })

  vim.api.nvim_create_autocmd({
    "CursorHold", "CursorHoldI", "FocusGained",
    "BufEnter", "InsertLeave", "TextChanged",
  }, {
    group = augroup,
    pattern = "*",
    callback = function()
      if vim.fn.filereadable(vim.fn.expand("%")) == 1 then
        vim.cmd("checktime")
      end
    end,
    desc = "Neph: check for file changes on disk",
  })

  -- Also check on a timer
  if timer then timer:stop(); timer:close(); timer = nil end
  timer = vim.loop.new_timer()
  if timer then
    timer:start(0, cfg.timer_interval or 1000, vim.schedule_wrap(function()
      vim.cmd("silent! checktime")
    end))
  end

  if cfg.updatetime then
    vim.o.updatetime = cfg.updatetime
  end
end

return M
