---@mod neph.backends.native Native Neovim splits (snacks.nvim)
---@brief [[
--- Opens AI agent terminals as right-split windows via snacks.nvim.
--- Used when WezTerm is not available or when inside an SSH session.
---@brief ]]

local M = {}
local config = {}

function M.setup(opts)
  config = opts or {}
end

---@param termname    string
---@param agent_config {cmd:string, args:string[], full_cmd:string}
---@param cwd         string
---@return table|nil
function M.open(termname, agent_config, cwd)
  local env = vim.tbl_extend("force", config.env or {}, {
    NVIM_SOCKET_PATH = vim.env.NVIM_SOCKET_PATH,
  })

  local term = Snacks.terminal.open(agent_config.cmd, {
    cwd = cwd,
    env = env,
    win = { position = "right", width = 0.5 },
  })

  return {
    buf  = term.buf,
    win  = term.win,
    term = term,
    cmd  = agent_config.cmd,
    cwd  = cwd,
    name = termname,
  }
end

function M.focus(term_data)
  if not M.is_visible(term_data) then return false end
  vim.api.nvim_set_current_win(term_data.win)
  return true
end

function M.hide(term_data)
  if term_data.win and vim.api.nvim_win_is_valid(term_data.win) then
    vim.api.nvim_win_close(term_data.win, true)
  end
  term_data.win  = nil
  term_data.buf  = nil
  term_data.term = nil
end

function M.show(_term_data)
  return nil -- reopen required
end

function M.is_visible(term_data)
  return term_data ~= nil
    and term_data.win ~= nil
    and vim.api.nvim_win_is_valid(term_data.win)
end

function M.kill(term_data)
  if term_data.win and vim.api.nvim_win_is_valid(term_data.win) then
    vim.api.nvim_win_close(term_data.win, true)
  end
end

function M.cleanup_all(terminals)
  for _, td in pairs(terminals) do
    if td.win and vim.api.nvim_win_is_valid(td.win) then
      vim.api.nvim_win_close(td.win, true)
    end
  end
end

return M
