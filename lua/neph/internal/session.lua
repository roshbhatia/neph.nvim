---@mod neph.session Session management
---@brief [[
--- Manages open agent terminal sessions.
--- The backend is injected via setup(opts, backend_mod) — no auto-detection.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

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
---@type table<string, {text:string, opts:table}[]>  termname → queued sends
local ready_queue = {}
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
    vim.api.nvim_create_autocmd({ "CursorHold", "FocusGained" }, {
      group = augroup,
      callback = function()
        for name, td in pairs(terminals) do
          if not backend.is_visible(td) then
            td.pane_id = nil
            td.win = nil
            td.stale_since = os.time()
            vim.g[name .. "_active"] = nil
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
        -- Clear vim.g state for all agents
        for name in pairs(terminals) do
          vim.g[name .. "_active"] = nil
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
        -- Stop filesystem watcher
        pcall(function()
          require("neph.internal.fs_watcher").stop()
        end)
      end,
    })
  end
end

-- ---------------------------------------------------------------------------
-- Core operations
-- ---------------------------------------------------------------------------

function M.open(termname)
  if not backend then
    vim.notify("Neph: not initialized (call setup first)", vim.log.levels.ERROR)
    return
  end
  local agent = require("neph.internal.agents").get_by_name(termname)
  if not agent then
    vim.notify("Neph: unknown agent – " .. termname, vim.log.levels.ERROR)
    return
  end

  if terminals[termname] and backend.is_visible(terminals[termname]) then
    M.focus(termname)
    return
  end

  -- Single-pane backends (e.g. Zellij): kill other agents before opening
  if backend.single_pane_only then
    for name, td in pairs(terminals) do
      if name ~= termname and backend.is_visible(td) then
        backend.kill(td)
        terminals[name] = nil
        if active_terminal == name then
          active_terminal = nil
        end
        vim.g[name .. "_active"] = nil
      end
    end
  end

  local cwd = vim.fn.getcwd()

  -- Resolve dynamic launch args if present
  local full_cmd = agent.full_cmd or agent.cmd
  local resolved_args = agent.args or {}
  if agent.launch_args_fn then
    local root = require("neph.tools").get_root()
    local ok, extra = pcall(agent.launch_args_fn, root)
    if ok and type(extra) == "table" then
      resolved_args = vim.list_extend(vim.deepcopy(resolved_args), extra)
      -- Rebuild full_cmd with dynamic args included
      local escaped = {}
      for i, arg in ipairs(resolved_args) do
        escaped[i] = vim.fn.shellescape(arg)
      end
      full_cmd = agent.cmd .. " " .. table.concat(escaped, " ")
    elseif not ok then
      log.debug("session", "launch_args_fn error for %s: %s", agent.name, tostring(extra))
      vim.notify("Neph: launch_args_fn failed for " .. agent.name .. ": " .. tostring(extra), vim.log.levels.WARN)
    end
  end

  -- Build agent_config expected by backends: { cmd, args, full_cmd, env, ready_pattern }
  local agent_config = {
    cmd = agent.full_cmd or agent.cmd,
    args = resolved_args,
    full_cmd = full_cmd,
    env = agent.env or {},
    ready_pattern = agent.ready_pattern,
  }

  log.debug("session", "open: %s (cmd=%s)", termname, agent_config.cmd)
  local td = backend.open(termname, agent_config, cwd)
  if td then
    terminals[termname] = td
    active_terminal = termname
    vim.g[termname .. "_active"] = true

    -- Start fs_watcher if this is the first active agent
    pcall(function()
      local fs_watcher = require("neph.internal.fs_watcher")
      if not fs_watcher.is_active() then
        fs_watcher.start()
      end
    end)

    -- Set on_ready callback to drain queued text
    td.on_ready = function()
      log.debug("session", "ready: %s", termname)
      local queue = ready_queue[termname]
      if queue then
        for _, entry in ipairs(queue) do
          M.send(termname, entry.text, entry.opts)
        end
        ready_queue[termname] = nil
      end
    end

    -- If already ready (no pattern or immediate match), fire now
    if td.ready then
      td.on_ready()
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
  log.debug("session", "focus: %s", termname)
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
  log.debug("session", "hide: %s", termname)
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
  log.debug("session", "kill_session: %s", termname)
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
  ready_queue[termname] = nil
  if active_terminal == termname then
    active_terminal = nil
  end
  vim.g[termname .. "_active"] = nil
  -- Force-cleanup active review UI if it belongs to this agent
  pcall(function()
    require("neph.api.review").force_cleanup(termname)
  end)
  -- Clear queued reviews for this agent
  pcall(function()
    require("neph.internal.review_queue").clear_agent(termname)
  end)
  -- Stop fs_watcher if no agents remain active
  pcall(function()
    local has_active = false
    for name in pairs(terminals) do
      if vim.g[name .. "_active"] then
        has_active = true
        break
      end
    end
    if not has_active then
      require("neph.internal.fs_watcher").stop()
    end
  end)
end

function M.send(termname, text, opts)
  opts = opts or {}
  local td = terminals[termname]
  if not td then
    return
  end

  log.debug("session", "send: %s via terminal (len=%d, submit=%s)", termname, #text, tostring(opts.submit or false))

  -- Default send: backend.send (WezTerm, Zellij) or native terminal via chansend
  if td.stale_since then
    log.debug("session", "send: %s skipped — terminal marked stale", termname)
    return
  end
  if backend.send then
    backend.send(td, text, opts)
    return
  end
  if td.buf and vim.api.nvim_buf_is_valid(td.buf) then
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
  local name = active_terminal
  require("neph.internal.terminal").set_last_prompt(name, text)

  if not M.exists(name) then
    M.open(name)
    M.focus(name)
  else
    M.focus(name)
  end

  local td = terminals[name]
  if not td then
    vim.notify("Neph: terminal failed to open", vim.log.levels.ERROR)
    return
  end

  if td.ready then
    M.send(name, text, { submit = true })
  else
    -- Queue text — on_ready callback will drain it
    if not ready_queue[name] then
      ready_queue[name] = {}
    end
    table.insert(ready_queue[name], { text = text, opts = { submit = true } })
    log.debug("session", "queued send for %s (ready=false, queue_len=%d)", name, #ready_queue[name])
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
