---@mod neph.backends.wezterm WezTerm pane backend
---@brief [[
--- Spawns AI agent terminals as WezTerm split-panes to the right of the
--- current Neovim pane.  Requires WEZTERM_PANE env var and `wezterm` CLI.
---@brief ]]

local M = {}
local config = {}
local parent_pane_id = nil
---@type table<number,number>
local pane_errors = {}
--- Maximum consecutive failures tracked per pane before the entry is discarded.
--- Caps table growth when many panes are opened and never explicitly killed.
local MAX_PANE_ERRORS = 10

local function get_current_pane()
  return tonumber(vim.env.WEZTERM_PANE)
end

local function cmd_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

--- Fire-and-forget: tell WezTerm to bring pane_id into focus.
--- Using jobstart (non-blocking) so focus never stalls the event loop.
local function activate_pane(pane_id)
  vim.fn.jobstart({ "wezterm", "cli", "activate-pane", "--pane-id", tostring(pane_id) })
end

--- Fire-and-forget: tell WezTerm to close pane_id.
local function kill_pane(pane_id)
  vim.fn.jobstart({ "wezterm", "cli", "kill-pane", "--pane-id", tostring(pane_id) })
end

--- Wait for a newly-spawned pane to appear in `wezterm cli list`.
--- Each poll launches a non-blocking job so the event loop is never stalled.
---@param pane_id number
---@param on_ready fun(ok: boolean)
---@param retries? number
local function wait_for_pane(pane_id, on_ready, retries)
  local max = retries or 5
  local attempts = 0
  local job_inflight = false
  local timer = vim.uv.new_timer()
  timer:start(
    100,
    100,
    vim.schedule_wrap(function()
      if job_inflight then
        return
      end
      attempts = attempts + 1
      if attempts > max then
        timer:stop()
        timer:close()
        on_ready(false)
        return
      end
      job_inflight = true
      vim.fn.jobstart({ "wezterm", "cli", "list", "--format", "json" }, {
        stdout_buffered = true,
        on_stdout = vim.schedule_wrap(function(_, data)
          local output = table.concat(data or {}, "\n")
          local ok, panes = pcall(vim.fn.json_decode, output)
          if not ok or type(panes) ~= "table" then
            return
          end
          for _, p in ipairs(panes) do
            if p.pane_id == pane_id then
              timer:stop()
              timer:close()
              on_ready(true)
              return
            end
          end
        end),
        on_exit = vim.schedule_wrap(function()
          job_inflight = false
        end),
      })
    end)
  )
end

local READY_POLL_MS = 200
local READY_TIMEOUT_MS = 30000

--- Poll `wezterm cli get-text` for a ready pattern in the pane output.
--- Each poll launches a non-blocking job; job_inflight prevents overlapping
--- polls when get-text takes longer than READY_POLL_MS.
--- Stores the timer handle on td.ready_timer so kill() can cancel it.
---@param td table  term_data (must have pane_id)
---@param pattern string  Lua pattern to match
local function watch_for_ready(td, pattern)
  local attempts = 0
  local max_attempts = READY_TIMEOUT_MS / READY_POLL_MS
  local job_inflight = false
  local timer = vim.uv.new_timer()
  td.ready_timer = timer

  local function stop_ready()
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
    td.ready_timer = nil
  end

  timer:start(
    READY_POLL_MS,
    READY_POLL_MS,
    vim.schedule_wrap(function()
      -- Guard: kill() sets pane_id to nil and _killed to true before this
      -- callback can observe either.  Check both so we bail without calling
      -- on_ready on a terminal that has already been torn down.
      if td._killed or not td.pane_id then
        stop_ready()
        return
      end

      -- Don't overlap: skip this tick if the previous get-text job is still running.
      if job_inflight then
        return
      end

      attempts = attempts + 1
      if attempts > max_attempts then
        stop_ready()
        if not td._killed then
          td.ready = true
          if td.on_ready then
            td.on_ready()
          end
        end
        return
      end

      job_inflight = true
      local pane_id = td.pane_id
      vim.fn.jobstart({ "wezterm", "cli", "get-text", "--pane-id", tostring(pane_id) }, {
        stdout_buffered = true,
        on_stdout = vim.schedule_wrap(function(_, data)
          if td._killed or not td.ready_timer then
            return
          end
          local text = table.concat(data or {}, "\n")
          for line in text:gmatch("[^\n]+") do
            if line:find(pattern) then
              stop_ready()
              td.ready = true
              if td.on_ready then
                td.on_ready()
              end
              return
            end
          end
        end),
        on_exit = vim.schedule_wrap(function()
          job_inflight = false
        end),
      })
    end)
  )
end

-- ---------------------------------------------------------------------------

---@param opts table  neph config passed from setup()
function M.setup(opts)
  config = opts or {}
  parent_pane_id = get_current_pane()
  pane_errors = {}
  if not parent_pane_id then
    vim.notify("Neph/wezterm: WEZTERM_PANE not set – falling back to native", vim.log.levels.WARN)
  end
end

---@param termname    string
---@param agent_config {cmd:string, args:string[], full_cmd:string, env:table<string,string>, ready_pattern?:string}
---@param cwd         string
---@return table|nil
function M.open(termname, agent_config, cwd)
  if not parent_pane_id then
    vim.notify("Neph/wezterm: cannot spawn – parent pane unavailable", vim.log.levels.ERROR)
    return nil
  end

  local bin = agent_config.cmd:match("^%S+")
  if not cmd_exists(bin) then
    vim.notify("Neph: command not found – " .. bin, vim.log.levels.ERROR)
    return nil
  end

  -- Build env prefix
  local env_parts = {}
  local merged_env = vim.tbl_extend("force", config.env or {}, agent_config.env or {})
  for k, v in pairs(merged_env) do
    env_parts[#env_parts + 1] = string.format("export %s=%s;", k, vim.fn.shellescape(v))
  end
  local nvim_socket = require("neph.internal.channel").socket_path()
  if nvim_socket and nvim_socket ~= "" then
    env_parts[#env_parts + 1] = string.format("export NVIM_SOCKET_PATH=%s;", vim.fn.shellescape(nvim_socket))
  end
  local env_str = table.concat(env_parts, " ")

  local agent_cmd = agent_config.full_cmd or agent_config.cmd
  local full_cmd = env_str ~= "" and (env_str .. " " .. agent_cmd) or agent_cmd
  -- NOTE: do NOT use 2>&1 here.  wezterm frequently emits warnings/config-reload
  -- notices to stderr.  Merging stderr into stdout would corrupt the pane ID that
  -- wezterm prints on stdout, causing tonumber() to return nil and the spawn to
  -- appear to fail even though wezterm actually created the pane.
  -- Redirect stderr to /dev/null to isolate the bare integer pane ID on stdout.
  local spawn_cmd = string.format(
    "wezterm cli split-pane --pane-id %d --right --percent 50 --cwd %s -- sh -c %s 2>/dev/null",
    parent_pane_id,
    vim.fn.shellescape(cwd),
    vim.fn.shellescape(full_cmd)
  )

  local result = vim.fn.system(spawn_cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify(
      "Neph/wezterm: spawn failed (exit " .. vim.v.shell_error .. ") – check :messages or run wezterm CLI manually",
      vim.log.levels.ERROR
    )
    return nil
  end

  local pane_id = tonumber(vim.trim(result))
  if not pane_id then
    vim.notify("Neph/wezterm: could not parse pane ID", vim.log.levels.ERROR)
    return nil
  end

  -- Return immediately — pane ID is known from split-pane output.
  -- Verify pane health asynchronously.
  local td = {
    pane_id = pane_id,
    cmd = agent_config.cmd,
    cwd = cwd,
    name = termname,
    created_at = os.time(),
    ready = not agent_config.ready_pattern,
    -- Set to true by kill() so queued schedule_wrap callbacks can detect that
    -- the pane has been torn down and skip on_ready invocation.
    _killed = false,
  }
  pane_errors[pane_id] = 0

  wait_for_pane(pane_id, function(ok)
    if not ok then
      vim.notify("Neph/wezterm: pane did not appear within timeout", vim.log.levels.WARN)
      local count = (pane_errors[pane_id] or 0) + 1
      if count < MAX_PANE_ERRORS then
        pane_errors[pane_id] = count
      else
        -- Discard the entry once we hit the cap to bound table size.
        pane_errors[pane_id] = nil
      end
    elseif agent_config.ready_pattern then
      watch_for_ready(td, agent_config.ready_pattern)
    end
  end, 5)

  return td
end

---@param term_data table|nil
---@return boolean  true if focus was set, false if terminal is not visible
function M.focus(term_data)
  if not M.is_visible(term_data) then
    return false
  end
  activate_pane(term_data.pane_id)
  return true
end

---@param term_data table|nil
function M.hide(term_data)
  if not term_data or not term_data.pane_id then
    return
  end
  -- WezTerm has no native pane-hide API.  Kill the pane so state stays
  -- consistent: callers expect hide() to remove the pane handle, and
  -- session.lua clears the terminals entry immediately after hide().
  term_data._killed = true
  if term_data.ready_timer then
    pcall(term_data.ready_timer.stop, term_data.ready_timer)
    pcall(term_data.ready_timer.close, term_data.ready_timer)
    term_data.ready_timer = nil
  end
  pane_errors[term_data.pane_id] = nil
  kill_pane(term_data.pane_id)
  term_data.pane_id = nil
end

---@param _term_data table|nil
---@return nil  wezterm backend requires reopen; show is a no-op
function M.show(_term_data)
  return nil
end

--- Trust the cached pane_id — no subprocess call. Pane death is detected
--- via send-text failures (on_exit) and the periodic async liveness check.
---@param term_data table|nil
---@return boolean
function M.is_visible(term_data)
  if not term_data or not term_data.pane_id then
    return false
  end
  return not term_data._killed
end

--- Async pane liveness check. Runs wezterm cli list in a non-blocking job
--- and calls callback(alive: boolean). Used by the periodic staleness timer
--- so it never blocks the Lua event loop.
---@param term_data table
---@param callback fun(alive: boolean)
function M.check_alive_async(term_data, callback)
  if not term_data or not term_data.pane_id then
    callback(false)
    return
  end
  local pane_id = term_data.pane_id
  vim.fn.jobstart({ "wezterm", "cli", "list", "--format", "json" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      local output = table.concat(data or {}, "\n")
      local ok, panes = pcall(vim.fn.json_decode, output)
      if not ok or type(panes) ~= "table" then
        return
      end
      for _, p in ipairs(panes) do
        if p.pane_id == pane_id then
          callback(true)
          return
        end
      end
      callback(false)
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        callback(false)
      end
    end,
  })
end

---@param term_data table|nil
function M.kill(term_data)
  if not term_data then
    return
  end
  -- Mark killed before clearing pane_id so the watch_for_ready schedule_wrap
  -- callback can detect teardown and skip the on_ready invocation.
  term_data._killed = true
  if term_data.ready_timer then
    pcall(term_data.ready_timer.stop, term_data.ready_timer)
    pcall(term_data.ready_timer.close, term_data.ready_timer)
    term_data.ready_timer = nil
  end
  if term_data.pane_id then
    pane_errors[term_data.pane_id] = nil
    kill_pane(term_data.pane_id)
  end
  term_data.pane_id = nil
end

---@param terminals table<string, table>  map of name -> term_data
function M.cleanup_all(terminals)
  if not terminals then
    return
  end
  for _, td in pairs(terminals) do
    td._killed = true
    if td.ready_timer then
      pcall(td.ready_timer.stop, td.ready_timer)
      pcall(td.ready_timer.close, td.ready_timer)
      td.ready_timer = nil
    end
    if td.pane_id then
      kill_pane(td.pane_id)
      td.pane_id = nil
    end
  end
  pane_errors = {}
end

---@param td table  term_data with pane_id
---@param text string
---@param opts? {submit?: boolean}
function M.send(td, text, opts)
  opts = opts or {}
  if not td or not td.pane_id then
    return
  end
  local full_text = opts.submit and (text .. "\n") or text
  local pane_id = td.pane_id
  local job_id = vim.fn.jobstart({
    "wezterm",
    "cli",
    "send-text",
    "--pane-id",
    tostring(pane_id),
    "--no-paste",
  }, {
    on_exit = vim.schedule_wrap(function(_, code)
      if code ~= 0 then
        local errors = (pane_errors[pane_id] or 0) + 1
        if errors >= 3 then
          -- Three consecutive failures → pane is gone; mark stale so session cleans up.
          td.stale_since = os.time()
          pane_errors[pane_id] = nil
          vim.notify("Neph: WezTerm pane unreachable — reopen with <leader>jj", vim.log.levels.WARN)
        else
          pane_errors[pane_id] = errors
          vim.notify(string.format("Neph: send to WezTerm failed (attempt %d/3)", errors), vim.log.levels.WARN)
        end
      else
        pane_errors[pane_id] = nil
      end
    end),
  })
  if job_id > 0 then
    vim.fn.chansend(job_id, full_text)
    vim.fn.chanclose(job_id, "stdin")
  else
    vim.notify("Neph: failed to start wezterm send-text", vim.log.levels.WARN)
  end
end

return M
