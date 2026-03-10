---@mod neph.backends.native Native Neovim splits (snacks.nvim)
---@brief [[
--- Opens AI agent terminals as right-split windows via snacks.nvim.
--- Used when WezTerm is not available or when inside an SSH session.
---@brief ]]

local M = {}
local config = {}

local READY_TIMEOUT_MS = 30000

function M.setup(opts)
  config = opts or {}
end

---@param termname    string
---@param agent_config {cmd:string, args:string[], full_cmd:string, env:table<string,string>, ready_pattern?:string}
---@param cwd         string
---@return table|nil
function M.open(termname, agent_config, cwd)
  local env = vim.tbl_extend("force", config.env or {}, agent_config.env or {}, {
    NVIM_SOCKET_PATH = vim.v.servername,
  })

  local term = Snacks.terminal.open(agent_config.full_cmd, {
    cwd = cwd,
    env = env,
    win = { position = "right", width = 0.5 },
  })

  local td = {
    buf = term.buf,
    win = term.win,
    term = term,
    cmd = agent_config.cmd,
    cwd = cwd,
    name = termname,
    ready = not agent_config.ready_pattern,
  }

  -- Watch terminal output for ready pattern
  if agent_config.ready_pattern and td.buf and vim.api.nvim_buf_is_valid(td.buf) then
    local pattern = agent_config.ready_pattern
    local matched = false

    -- Attach to terminal buffer output
    vim.api.nvim_buf_attach(td.buf, false, {
      on_lines = function(_, buf)
        if matched or not vim.api.nvim_buf_is_valid(buf) then
          return true -- detach
        end
        local line_count = vim.api.nvim_buf_line_count(buf)
        -- Check last few lines for the pattern
        local start = math.max(0, line_count - 5)
        local lines = vim.api.nvim_buf_get_lines(buf, start, line_count, false)
        for _, line in ipairs(lines) do
          if line:find(pattern) then
            matched = true
            td.ready = true
            if td.on_ready then
              td.on_ready()
            end
            return true -- detach
          end
        end
      end,
    })

    -- Timeout: fail-open after 30s
    td.ready_timer = vim.uv.new_timer()
    td.ready_timer:start(
      READY_TIMEOUT_MS,
      0,
      vim.schedule_wrap(function()
        if td.ready_timer then
          td.ready_timer:close()
          td.ready_timer = nil
        end
        if not matched then
          matched = true
          td.ready = true
          if td.on_ready then
            td.on_ready()
          end
        end
      end)
    )
  end

  return td
end

function M.focus(term_data)
  if not M.is_visible(term_data) then
    return false
  end
  vim.api.nvim_set_current_win(term_data.win)
  return true
end

function M.hide(term_data)
  if term_data.win and vim.api.nvim_win_is_valid(term_data.win) then
    vim.api.nvim_win_close(term_data.win, true)
  end
  term_data.win = nil
  term_data.buf = nil
  term_data.term = nil
end

function M.show(_term_data)
  return nil -- reopen required
end

function M.is_visible(term_data)
  return term_data ~= nil and term_data.win ~= nil and vim.api.nvim_win_is_valid(term_data.win)
end

function M.kill(term_data)
  if term_data.ready_timer then
    pcall(term_data.ready_timer.stop, term_data.ready_timer)
    pcall(term_data.ready_timer.close, term_data.ready_timer)
    term_data.ready_timer = nil
  end
  if term_data.win and vim.api.nvim_win_is_valid(term_data.win) then
    vim.api.nvim_win_close(term_data.win, true)
  end
  term_data.win = nil
  term_data.buf = nil
  term_data.term = nil
end

function M.cleanup_all(terminals)
  for _, td in pairs(terminals) do
    if td.win and vim.api.nvim_win_is_valid(td.win) then
      vim.api.nvim_win_close(td.win, true)
    end
  end
end

return M
