---@mod neph.backends.tmux tmux backend (stub)
---@brief [[
--- Placeholder backend for tmux multiplexer support.
--- Emits a warning and falls back to the native backend.
--- Full tmux pane management is not yet implemented.
---@brief ]]

local M = {}

function M.setup(_opts)
  vim.notify(
    "Neph: tmux backend is not yet implemented – falling back to native (snacks.nvim splits).",
    vim.log.levels.WARN
  )
end

function M.open(_termname, _agent_config, _cwd)
  return nil
end

function M.focus(_term_data)
  return false
end

function M.hide(_term_data) end

function M.show(_term_data)
  return nil
end

function M.is_visible(_term_data)
  return false
end

function M.kill(_term_data) end

function M.cleanup_all(_terminals) end

return M
