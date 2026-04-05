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
---@type userdata|nil  periodic staleness check timer
local stale_timer = nil
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
        local keys = vim.tbl_keys(terminals)
        for _, name in ipairs(keys) do
          local td = terminals[name]
          if td then
            if not backend.is_visible(td) then
              td.stale_since = os.time()
              vim.g[name .. "_active"] = nil
              if active_terminal == name then
                active_terminal = nil
              end
            elseif td.stale_since then
              td.stale_since = nil
            end
          end
        end
      end,
    })

    -- Detect native (snacks) terminal processes that die unexpectedly.
    -- When the agent process exits, Neovim fires TermClose on the terminal
    -- buffer. Without this handler the window remains visually open and
    -- is_visible() still returns true, so send() would keep trying to
    -- chansend into a dead job and ready_queue entries would be drained
    -- into the void.  Mark the terminal stale immediately so subsequent
    -- send/focus calls treat the session as gone.
    vim.api.nvim_create_autocmd("TermClose", {
      group = augroup,
      callback = function(ev)
        local closed_buf = ev.buf
        for name, td in pairs(terminals) do
          if td and td.buf == closed_buf then
            log.debug("session", "TermClose: agent process exited for %s (buf=%d)", name, closed_buf)
            -- Cancel the ready-timer if it is still running.
            if td.ready_timer then
              pcall(td.ready_timer.stop, td.ready_timer)
              pcall(td.ready_timer.close, td.ready_timer)
              td.ready_timer = nil
            end
            -- Drop any queued sends that would target the dead channel.
            ready_queue[name] = nil
            -- Mark stale so all callers observe the dead state without a
            -- backend.is_visible() round-trip.
            td.stale_since = os.time()
            vim.g[name .. "_active"] = nil
            if active_terminal == name then
              active_terminal = nil
            end
            break
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
        -- Stop periodic staleness timer
        if stale_timer then
          pcall(stale_timer.stop, stale_timer)
          pcall(stale_timer.close, stale_timer)
          stale_timer = nil
        end
        -- Reject all pending queued reviews BEFORE tearing down backend
        -- so CLI callers receive a reject response before panes/channels close.
        pcall(function()
          require("neph.internal.review_queue").reject_all_pending("Neovim exiting")
        end)
        -- Wrap backend.cleanup_all so failures don't block remaining teardown
        pcall(backend.cleanup_all, terminals)
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
        -- Clear gate winbar indicator so the previous winbar value is restored
        -- before Neovim tears down windows (best-effort; window may already be
        -- invalid, which pcall swallows).
        pcall(function()
          require("neph.internal.gate_ui").clear()
        end)
      end,
    })

    -- Periodic staleness check: mark panes stale every 30 s without waiting
    -- for user interaction (CursorHold/FocusGained).
    if vim.uv then
      stale_timer = vim.uv.new_timer()
      if stale_timer then
        stale_timer:start(
          30000,
          30000,
          vim.schedule_wrap(function()
            local keys = vim.tbl_keys(terminals)
            for _, name in ipairs(keys) do
              local td = terminals[name]
              if td then
                if not backend.is_visible(td) then
                  td.stale_since = os.time()
                  vim.g[name .. "_active"] = nil
                  if active_terminal == name then
                    active_terminal = nil
                  end
                elseif td.stale_since then
                  td.stale_since = nil
                end
              end
            end
          end)
        )
      end
    end
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

    -- For opencode_sse agents: subscribe to the opencode SSE event stream so
    -- neph can intercept writes via the permission API (pre-write, no Cupcake).
    if agent.integration_group == "opencode_sse" then
      pcall(function()
        local sse = require("neph.internal.opencode_sse")
        local perm = require("neph.reviewers.opencode_permission")
        local port = sse.discover_port()
        if port then
          sse.subscribe(port, function(event_type, data)
            perm.handle_event(port, event_type, data)
          end)
          log.debug("session", "opencode SSE subscribed on port %d", port)
        else
          log.debug("session", "opencode SSE: no server found (opencode launched without --port)")
        end
      end)
    end

    -- Set on_ready callback to drain queued text.
    -- The queue may already contain entries added before open() was called
    -- (e.g. via ensure_active_and_send racing with a slow open).
    td.on_ready = function()
      log.debug("session", "ready: %s", termname)
      local queue = ready_queue[termname]
      if queue then
        ready_queue[termname] = nil
        for _, entry in ipairs(queue) do
          local ok, err = pcall(M.send, termname, entry.text, entry.opts)
          if not ok then
            log.warn("session", "on_ready send failed for %s: %s", termname, tostring(err))
          end
        end
      end
    end

    -- If already ready (no pattern or immediate match), fire now
    if td.ready then
      td.on_ready()
    end
  else
    -- backend.open returned nil: clear any stale terminals entry so a
    -- subsequent open() is not short-circuited by the stale record.
    terminals[termname] = nil
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
    M.open(termname)
    return
  end
  if not backend.focus(td) then
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
    -- Wrap in pcall: a backend failure must not prevent cleanup below.
    local ok, err = pcall(backend.kill, td)
    if not ok then
      log.debug("session", "kill_session: backend.kill error for %s: %s", termname, tostring(err))
    end
  end
  terminals[termname] = nil
  ready_queue[termname] = nil
  if active_terminal == termname then
    active_terminal = nil
  end
  vim.g[termname .. "_active"] = nil
  -- Clear the stored last-prompt so a subsequent resend() on a new session
  -- does not replay a prompt that belonged to the killed session.
  pcall(function()
    require("neph.internal.terminal").set_last_prompt(termname, nil)
  end)
  -- Unsubscribe opencode SSE stream if this was an SSE-integrated agent
  pcall(function()
    local agent = require("neph.internal.agents").get_registered_by_name(termname)
    if agent and agent.integration_group == "opencode_sse" then
      require("neph.internal.opencode_sse").unsubscribe()
      log.debug("session", "opencode SSE unsubscribed for %s", termname)
    end
  end)
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

  if td.stale_since then
    log.debug("session", "send: %s skipped — terminal marked stale", termname)
    return
  end
  if not backend.is_visible(td) then
    return
  end
  backend.send(td, text, opts)
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
    cmd = td.cmd,
    cwd = td.cwd,
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
