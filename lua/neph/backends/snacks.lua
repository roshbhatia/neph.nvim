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
    NVIM_SOCKET_PATH = require("neph.internal.channel").socket_path(),
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
    -- Set to true by kill() so queued schedule_wrap callbacks can detect that
    -- the terminal has been torn down and skip on_ready invocation.
    _killed = false,
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
        -- Guard: kill() may have been called while this callback was queued.
        -- Do not invoke on_ready on a terminal that has already been torn down.
        if not matched and not td._killed then
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
  if not term_data or not term_data.win then
    return
  end
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
  if not term_data then
    return
  end
  -- Mark killed first so any queued schedule_wrap timer callbacks observe it
  -- before they attempt to call on_ready.
  term_data._killed = true
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

---@param td table  term_data with buf
---@param text string
---@param opts? {submit?: boolean}
function M.send(td, text, opts)
  opts = opts or {}
  if not td or not td.buf or not vim.api.nvim_buf_is_valid(td.buf) then
    return
  end
  local chan = vim.b[td.buf].terminal_job_id
  if not chan then
    return
  end
  local full_text = opts.submit and (text .. "\n") or text
  -- chansend returns 0 and errors when the job has exited but the buffer is still
  -- valid (stale terminal_job_id). Wrap in pcall so callers are not interrupted.
  pcall(vim.fn.chansend, chan, full_text)
end

function M.cleanup_all(terminals)
  if not terminals then
    return
  end
  for _, td in pairs(terminals) do
    if td.ready_timer then
      pcall(td.ready_timer.stop, td.ready_timer)
      pcall(td.ready_timer.close, td.ready_timer)
      td.ready_timer = nil
    end
    if td.win and vim.api.nvim_win_is_valid(td.win) then
      vim.api.nvim_win_close(td.win, true)
    end
  end
end

return M
