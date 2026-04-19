---@mod neph.session Session management
---@brief [[
--- Manages open agent terminal sessions.
--- The backend is injected via setup(opts, backend_mod) — no auto-detection.
---
--- Session lifecycle state machine:
---   ABSENT  → open()          → OPENING (backend.open called)
---   OPENING → (ready signal)  → READY
---   READY   → kill_session()  → ABSENT  (idempotent; safe to call twice)
---   READY   → hide()          → ABSENT  (pane destroyed; re-open required)
---   READY   → TermClose       → STALE   (process exited unexpectedly)
---   STALE   → kill_session()  → ABSENT
---
--- Valid transitions summary:
---   open():         ABSENT → OPENING/READY
---   kill_session(): any    → ABSENT  (idempotent)
---   hide():         READY  → ABSENT
---   focus():        READY  → READY   (no state change; reopens if invisible)
---   toggle():       ABSENT → READY   | READY → READY (focus)
---@brief ]]

---@class neph.TermData
---@field pane_id    number|string|nil  Backend-specific pane handle (nil when killed/hidden)
---@field buf        integer|nil        Neovim buffer handle (snacks backend only)
---@field win        integer|nil        Neovim window handle (snacks backend only)
---@field cmd        string|nil         Executable name used to spawn the agent (may be nil from backend)
---@field cwd        string|nil         Working directory at spawn time (may be nil from backend)
---@field name       string|nil         Terminal name — same as the key in `terminals` (may be nil from backend)
---@field created_at integer|nil        os.time() at spawn
---@field ready      boolean            True once the agent has printed its ready prompt
---@field on_ready   fun()|nil          Callback set by open(); drains ready_queue
---@field ready_timer userdata|nil      Active vim.uv timer waiting for ready_pattern match
---@field stale_since integer|nil       os.time() when pane was detected dead; nil if healthy
---@field _killed    boolean|nil        True after kill(); guards deferred async callbacks

local M = {}

local log = require("neph.internal.log")

---@type table  Backend module (neph.backends.wezterm or neph.backends.native)
local backend = nil
---@type neph.Config
local config = {}
---@type table<string, neph.TermData>  termname → term_data
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
-- Private helpers
-- ---------------------------------------------------------------------------

--- Stop and close a uv timer, swallowing errors. Returns nil for easy chaining.
---@param t userdata|nil  Timer handle
---@return nil
local function cancel_timer(t)
  if not t then
    return
  end
  pcall(t.stop, t)
  pcall(t.close, t)
end

--- Mark a terminal stale and clear its active state.
---@param name string
---@param td neph.TermData
local function mark_stale(name, td)
  td.stale_since = os.time()
  vim.g[name .. "_active"] = nil
  if active_terminal == name then
    active_terminal = nil
  end
end

--- Drain the ready_queue for *termname*, sending each queued entry via M.send.
--- Called from the on_ready callback set on each terminal after open().
---@param termname string
local function drain_ready_queue(termname)
  local queue = ready_queue[termname]
  if not queue then
    return
  end
  ready_queue[termname] = nil
  for _, entry in ipairs(queue) do
    local ok, err = pcall(M.send, termname, entry.text, entry.opts)
    if not ok then
      log.warn("session", "on_ready send failed for %s: %s", termname, tostring(err))
    end
  end
end

--- Build the agent_config table expected by backends, resolving dynamic launch args.
---@param agent table  Registered agent definition
---@return table  { cmd, args, full_cmd, env, ready_pattern }
local function build_agent_config(agent)
  local full_cmd = agent.full_cmd or agent.cmd
  local resolved_args = agent.args or {}
  if agent.launch_args_fn then
    local root = require("neph.tools").get_root()
    local ok, extra = pcall(agent.launch_args_fn, root)
    if ok and type(extra) == "table" then
      resolved_args = vim.list_extend(vim.deepcopy(resolved_args), extra)
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
  return {
    cmd = agent.full_cmd or agent.cmd,
    args = resolved_args,
    full_cmd = full_cmd,
    env = agent.env or {},
    ready_pattern = agent.ready_pattern,
  }
end

--- Run an async liveness check on every tracked terminal.
--- For each terminal that responds "alive=false", call mark_stale().
--- For terminals that recover (stale_since set but now alive), clear stale_since.
--- The callback guards against _killed so a result arriving after kill_session()
--- does not act on a td that is no longer owned by the session table.
local function check_all_alive()
  if not backend or not backend.check_alive_async then
    return
  end
  local keys = vim.tbl_keys(terminals)
  for _, name in ipairs(keys) do
    local td = terminals[name]
    if td then
      backend.check_alive_async(td, function(alive)
        -- Drop callbacks for sessions that were killed while the async request
        -- was in flight — td._killed is set before the terminals entry is removed.
        if td._killed then
          return
        end
        if not alive then
          mark_stale(name, td)
        elseif td.stale_since then
          td.stale_since = nil
        end
      end)
    end
  end
end

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

    -- Async pane health check on focus events — never blocks the event loop.
    vim.api.nvim_create_autocmd({ "CursorHold", "FocusGained" }, {
      group = augroup,
      callback = check_all_alive,
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
            cancel_timer(td.ready_timer)
            td.ready_timer = nil
            -- Drop any queued sends that would target the dead channel.
            ready_queue[name] = nil
            -- Mark stale so all callers observe the dead state without a
            -- backend.is_visible() round-trip.
            mark_stale(name, td)
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
        cancel_timer(stale_timer)
        stale_timer = nil
        -- Reject all pending queued reviews BEFORE tearing down backend
        -- so CLI callers receive a reject response before panes/channels close.
        pcall(function()
          require("neph.internal.review_queue").reject_all_pending("Neovim exiting")
        end)
        -- Wrap backend.cleanup_all so failures don't block remaining teardown
        pcall(backend.cleanup_all, terminals)
        -- Clean up all pending timers
        for name, pt in pairs(pending_timers) do
          cancel_timer(pt)
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

    -- Periodic staleness check: async liveness ping every 30 s so the timer
    -- callback never blocks the Lua event loop with a synchronous subprocess.
    if vim.uv then
      stale_timer = vim.uv.new_timer()
      if stale_timer then
        stale_timer:start(30000, 30000, vim.schedule_wrap(check_all_alive))
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Core operations
-- ---------------------------------------------------------------------------

---@param termname string
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

  -- Single-pane backends (e.g. Zellij): kill other agents before opening.
  -- Cancel the ready-timer and set _killed before backend.kill so deferred
  -- callbacks cannot act on the evicted td. backend.kill is wrapped in pcall
  -- so a throw cannot leave terminals[] in a partially-mutated state.
  if backend.single_pane_only then
    for name, td in pairs(terminals) do
      if name ~= termname and backend.is_visible(td) then
        td._killed = true
        cancel_timer(td.ready_timer)
        td.ready_timer = nil
        local ok, err = pcall(backend.kill, td)
        if not ok then
          log.debug("session", "single_pane_only kill error for %s: %s", name, tostring(err))
        end
        terminals[name] = nil
        ready_queue[name] = nil
        if active_terminal == name then
          active_terminal = nil
        end
        vim.g[name .. "_active"] = nil
      end
    end
  end

  local cwd = vim.fn.getcwd()
  local agent_config = build_agent_config(agent)

  -- If a stale/invisible entry exists for this terminal, cancel its ready-timer
  -- before we start a fresh backend.open so the timer cannot fire on_ready for
  -- the old td after the new session is registered.
  local stale_td = terminals[termname]
  if stale_td and stale_td.ready_timer then
    cancel_timer(stale_td.ready_timer)
    stale_td.ready_timer = nil
  end

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
    -- Chain any existing on_ready set by the backend so both fire.
    local backend_on_ready = td.on_ready
    td.on_ready = function()
      -- Guard: do not fire for sessions already killed while this callback was pending.
      if td._killed then
        return
      end
      log.debug("session", "ready: %s", termname)
      if backend_on_ready then
        pcall(backend_on_ready)
      end
      drain_ready_queue(termname)
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

---@param termname string
function M.toggle(termname)
  local td = terminals[termname]
  if td and backend and backend.is_visible(td) then
    M.focus(termname)
  else
    M.open(termname)
  end
end

---@param termname string
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

--- Hide a named agent terminal and remove it from session tracking.
--- Clears vim.g[name.."_active"] so statusline integrations reflect the change.
--- Cancels any pending ready_timer so it cannot fire on_ready after the session
--- is removed from the tracking table.
---@param termname string
function M.hide(termname)
  log.debug("session", "hide: %s", termname)
  local td = terminals[termname]
  if not td or not backend then
    return
  end
  -- Cancel ready-timer before hiding so it cannot drain the queue into a dead
  -- pane after terminals[termname] is cleared.
  if td.ready_timer then
    cancel_timer(td.ready_timer)
    td.ready_timer = nil
  end
  ready_queue[termname] = nil
  backend.hide(td)
  terminals[termname] = nil
  vim.g[termname .. "_active"] = nil
  if active_terminal == termname then
    active_terminal = nil
  end
end

--- Activate a named agent terminal (open or focus) and mark it as active.
--- Only updates active_terminal when the terminal is successfully tracked after
--- open/focus — if backend.open returns nil the active terminal is not changed.
---@param termname string
function M.activate(termname)
  local td = terminals[termname]
  if not td or not backend or not backend.is_visible(td) then
    M.open(termname)
  else
    M.focus(termname)
  end
  -- Guard: only mark as active when the terminal was actually registered.
  -- If open() failed (backend returned nil) terminals[termname] is still nil
  -- and we must not claim an active session that does not exist.
  if terminals[termname] then
    active_terminal = termname
  end
end

--- Kill a named agent terminal session and clean up all associated state.
--- Idempotent: safe to call on an already-killed terminal or a terminal that
--- was never opened. backend.kill is wrapped in pcall so a backend failure
--- cannot prevent the in-process state from being fully reset.
---@param termname string
function M.kill_session(termname)
  log.debug("session", "kill_session: %s", termname)
  -- Cancel any pending retry timer
  cancel_timer(pending_timers[termname])
  pending_timers[termname] = nil

  local td = terminals[termname]
  if td then
    -- Set _killed FIRST so deferred async callbacks (check_alive_async result,
    -- on_ready timer) that arrive after this point see the dead flag and exit
    -- without side-effects. This must happen before backend.kill so the flag is
    -- visible even if backend.kill throws.
    td._killed = true
    -- Cancel the ready-timer BEFORE backend.kill so it cannot fire on_ready
    -- on an already-destroyed session even if backend.kill itself throws.
    cancel_timer(td.ready_timer)
    td.ready_timer = nil
    if backend then
      -- Wrap in pcall: a backend failure must not prevent cleanup below.
      local ok, err = pcall(backend.kill, td)
      if not ok then
        log.debug("session", "kill_session: backend.kill error for %s: %s", termname, tostring(err))
      end
    end
  end
  terminals[termname] = nil
  ready_queue[termname] = nil
  if active_terminal == termname then
    active_terminal = nil
  end
  vim.g[termname .. "_active"] = nil
  vim.g[termname .. "_running"] = nil
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

--- Send text to a named agent terminal. No-op when:
---   • termname is nil or not tracked
---   • the terminal is marked stale
---   • the terminal window is no longer visible
---@param termname string|nil
---@param text     string  Text to send to the terminal process
---@param opts?    {submit?: boolean}  When submit=true the backend appends a newline
function M.send(termname, text, opts)
  if not termname then
    return
  end
  opts = opts or {}
  local td = terminals[termname]
  if not td then
    return
  end

  log.debug("session", "send: %s via terminal (len=%d, submit=%s)", termname, #text, tostring(opts.submit or false))

  if td.stale_since then
    log.debug("session", "send: %s skipped — terminal marked stale", termname)
    vim.notify("Neph: terminal is stale — reopen with <leader>jj", vim.log.levels.WARN)
    return
  end
  if not backend.is_visible(td) then
    vim.notify("Neph: terminal window is not visible — open it first", vim.log.levels.WARN)
    return
  end
  backend.send(td, text, opts)
end

--- Ensure the active agent terminal is open and send text to it.
--- Queues the text until the terminal is ready if it was just opened.
---@param text string  Prompt text to send (submitted automatically)
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

--- Return the name of the currently active terminal, or nil if none.
---@return string|nil
function M.get_active()
  return active_terminal
end

--- Alias of get_active() for explicitness in lifecycle-aware callers.
--- Always returns nil when no session is active — never crashes.
---@return string|nil
function M.get_active_session()
  return active_terminal
end

--- Set the active terminal by name.
--- No-op (with a debug log) when the terminal is not currently tracked,
--- so callers cannot set an active session that does not exist.
---@param n string
function M.set_active(n)
  if terminals[n] then
    active_terminal = n
  else
    log.debug("session", "set_active: %s is not a tracked terminal — ignored", tostring(n))
  end
end

---@param termname string
---@return boolean
function M.is_visible(termname)
  local td = terminals[termname]
  return td and backend and backend.is_visible(td) or false
end

---@param termname string
---@return boolean
function M.is_tracked(termname)
  local td = terminals[termname]
  if not td then
    return false
  end
  return backend and backend.is_visible(td) or false
end

---@param termname string
---@return boolean
function M.exists(termname)
  return M.is_visible(termname)
end

---@param termname string
---@return {name:string, visible:boolean, cmd:string, cwd:string}|nil
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

---@return table<string, {name:string, visible:boolean, cmd:string, cwd:string}|nil>
function M.get_all()
  local result = {}
  for name in pairs(terminals) do
    result[name] = M.get_info(name)
  end
  return result
end

return M
