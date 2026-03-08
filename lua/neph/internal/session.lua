---@mod neph.session Session management
---@brief [[
--- Manages open agent terminal sessions.  Auto-detects the best backend:
---   1. SSH connections → always native (snacks.nvim splits)
---   2. WezTerm available → wezterm pane backend
---   3. Fallback → native backend
---@brief ]]

local M = {}

---@type table  Backend module (neph.backends.wezterm or neph.backends.native)
local backend = nil
---@type neph.Config
local config = {}
---@type table<string, table>  termname → term_data
local terminals = {}
---@type string|nil
local active_terminal = nil
---@type integer|nil
local augroup = nil
---@type table<string, userdata>  termname → pending retry timer
local pending_timers = {}

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

---@param opts neph.Config
---@param backend_mod table  Injected backend module
function M.setup(opts, backend_mod)
  config = opts or {}
  config.env = config.env or {}

  backend = backend_mod
  backend.setup(config)

  if not augroup then
    augroup = vim.api.nvim_create_augroup("NephSession", { clear = true })

    -- Periodically check pane health
    vim.api.nvim_create_autocmd("CursorHold", {
      group = augroup,
      callback = function()
        for name, td in pairs(terminals) do
          if not backend.is_visible(td) then
            td.pane_id = nil
            td.win = nil
            td.stale_since = os.time()
            if active_terminal == name then
              active_terminal = nil
            end
          elseif td.stale_since then
            td.stale_since = nil
          end
        end
      end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = augroup,
      callback = function()
        -- Clear vim.g state for terminal-only agents
        for name in pairs(terminals) do
          local agent = require("neph.internal.agents").get_by_name(name)
          if agent and not agent.integration then
            vim.g[name .. "_active"] = nil
          end
        end
        backend.cleanup_all(terminals)
        -- Clean up all pending timers
        for name, pt in pairs(pending_timers) do
          pcall(pt.stop, pt)
          pcall(pt.close, pt)
          pending_timers[name] = nil
        end
        -- Tear down file refresh polling
        pcall(function()
          require("neph.internal.file_refresh").teardown()
        end)
      end,
    })
  end
end

-- ---------------------------------------------------------------------------
-- Core operations
-- ---------------------------------------------------------------------------

function M.open(termname)
  local agent = require("neph.internal.agents").get_by_name(termname)
  if not agent then
    vim.notify("Neph: unknown agent – " .. termname, vim.log.levels.ERROR)
    return
  end

  if terminals[termname] and backend.is_visible(terminals[termname]) then
    M.focus(termname)
    return
  end

  local cwd = vim.fn.getcwd()

  -- Build agent_config expected by backends: { cmd, args, full_cmd }
  local agent_config = {
    cmd = agent.full_cmd or agent.cmd,
    args = agent.args or {},
    full_cmd = agent.full_cmd or agent.cmd,
  }

  local td = backend.open(termname, agent_config, cwd)
  if td then
    terminals[termname] = td
    active_terminal = termname
    -- Terminal-only agents: set vim.g state (hook/extension agents manage their own)
    if not agent.integration then
      vim.g[termname .. "_active"] = true
    end
  end
end

function M.toggle(termname)
  local td = terminals[termname]
  if td and backend and backend.is_visible(td) then
    M.focus(termname)
  else
    M.open(termname)
  end
end

function M.focus(termname)
  local td = terminals[termname]
  if not td or not backend then
    return
  end
  if not backend.is_visible(td) then
    td.pane_id = nil
    td.win = nil
    M.open(termname)
    return
  end
  if not backend.focus(td) then
    td.pane_id = nil
    td.win = nil
    M.open(termname)
    return
  end
  active_terminal = termname
end

function M.hide(termname)
  local td = terminals[termname]
  if not td or not backend then
    return
  end
  backend.hide(td)
  terminals[termname] = nil
  if active_terminal == termname then
    active_terminal = nil
  end
end

function M.activate(termname)
  local td = terminals[termname]
  if not td or not backend or not backend.is_visible(td) then
    M.open(termname)
  else
    M.focus(termname)
  end
  active_terminal = termname
end

function M.kill_session(termname)
  -- Cancel any pending retry timer
  local pt = pending_timers[termname]
  if pt then
    pcall(pt.stop, pt)
    pcall(pt.close, pt)
    pending_timers[termname] = nil
  end

  local td = terminals[termname]
  if td and backend then
    backend.kill(td)
  end
  terminals[termname] = nil
  if active_terminal == termname then
    active_terminal = nil
  end
  -- Terminal-only agents: clear vim.g state
  local agent = require("neph.internal.agents").get_by_name(termname)
  if agent and not agent.integration then
    vim.g[termname .. "_active"] = nil
  end
end

function M.send(termname, text, opts)
  opts = opts or {}
  local td = terminals[termname]
  if not td then
    return
  end

  -- Check for agent-specific send adapter
  local agent = require("neph.internal.agents").get_by_name(termname)
  local adapter = agent and agent.send_adapter
  if adapter then
    local sent = adapter(td, text, opts)
    if sent then
      return
    end
    -- Adapter returned false/nil: fall through to default send
  end

  -- Default send: WezTerm pane or native terminal via chansend
  if td.pane_id then
    local full_text = opts.submit and (text .. "\n") or text
    local job_id = vim.fn.jobstart({
      "wezterm", "cli", "send-text",
      "--pane-id", tostring(td.pane_id),
      "--no-paste",
    }, {
      on_exit = vim.schedule_wrap(function(_, code)
        if code ~= 0 then
          vim.notify("Neph: wezterm send-text failed (exit " .. code .. ")", vim.log.levels.WARN)
        end
      end),
    })
    if job_id > 0 then
      vim.fn.chansend(job_id, full_text)
      vim.fn.chanclose(job_id, "stdin")
    end
  elseif td.buf and vim.api.nvim_buf_is_valid(td.buf) then
    local chan = vim.b[td.buf].terminal_job_id
    if chan then
      vim.fn.chansend(chan, text)
      if opts.submit then
        vim.fn.chansend(chan, "\n")
      end
    end
  end
end

function M.ensure_active_and_send(text)
  if not active_terminal then
    vim.notify("Neph: no active terminal – pick one with <leader>jj", vim.log.levels.WARN)
    return
  end
  if not M.exists(active_terminal) then
    M.open(active_terminal)
    M.focus(active_terminal)
    -- Use a non-blocking timer to wait for the terminal to become ready
    local retries = 0
    local max_retries = 20
    local name = active_terminal
    local timer = vim.loop.new_timer()
    pending_timers[name] = timer
    timer:start(50, 50, vim.schedule_wrap(function()
      retries = retries + 1
      if M.exists(name) then
        timer:stop()
        timer:close()
        pending_timers[name] = nil
        M.send(name, text, { submit = true })
      elseif retries >= max_retries then
        timer:stop()
        timer:close()
        pending_timers[name] = nil
        vim.notify("Neph: terminal failed to become ready", vim.log.levels.ERROR)
      end
    end))
  else
    M.focus(active_terminal)
    M.send(active_terminal, text, { submit = true })
  end
end

-- ---------------------------------------------------------------------------
-- Query helpers
-- ---------------------------------------------------------------------------

function M.get_active()
  return active_terminal
end
function M.set_active(n)
  if terminals[n] then
    active_terminal = n
  end
end

function M.is_visible(termname)
  local td = terminals[termname]
  return td and backend and backend.is_visible(td) or false
end

function M.is_tracked(termname)
  local td = terminals[termname]
  if not td then
    return false
  end
  return backend and backend.is_visible(td) or false
end

function M.exists(termname)
  return M.is_visible(termname)
end

function M.get_info(termname)
  local td = terminals[termname]
  if not td or not backend then
    return nil
  end
  return {
    name = termname,
    visible = backend.is_visible(td),
    pane_id = td.pane_id,
    cmd = td.cmd,
    cwd = td.cwd,
    win = td.win,
    buf = td.buf,
  }
end

function M.get_all()
  local result = {}
  for name in pairs(terminals) do
    result[name] = M.get_info(name)
  end
  return result
end

return M
