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
  -- Idempotent: tear down any existing state first
  M.teardown()

  local cfg = (config or {}).file_refresh or {}
  if not cfg.enable then
    return
  end

  local augroup = vim.api.nvim_create_augroup("NephFileRefresh", { clear = true })

  vim.api.nvim_create_autocmd({
    "CursorHold",
    "CursorHoldI",
    "FocusGained",
    "BufEnter",
  }, {
    group = augroup,
    pattern = "*",
    callback = function()
      vim.cmd("silent! checktime")
    end,
    desc = "Neph: check for file changes on disk",
  })

  -- Also check on a timer
  timer = vim.uv.new_timer()
  if timer then
    local interval = cfg.interval or 1000
    timer:start(
      interval,
      interval,
      vim.schedule_wrap(function()
        vim.cmd("silent! checktime")
      end)
    )
  end
end

--- Stop the polling timer and clear the autocmd group.
--- Safe to call multiple times (idempotent).
function M.teardown()
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
    timer = nil
  end
  pcall(vim.api.nvim_del_augroup_by_name, "NephFileRefresh")
end

return M
