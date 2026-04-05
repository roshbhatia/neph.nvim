-- lua/neph/internal/opencode_sse.lua
-- Subscribes to the opencode HTTP/SSE event stream so neph can intercept
-- file writes (permission.asked) and trigger buffer reloads (file.edited)
-- without requiring the Cupcake harness.

local M = {}

local log = require("neph.internal.log")

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local state = {
  port = nil, -- discovered port (integer)
  job_id = nil, -- curl jobstart id
  retries = 0,
  retry_timer = nil,
  on_event = nil, -- callback: fn(event_type, data_table)
}

local MAX_RETRIES = 5
local RETRY_DELAY_MS = 2000

-- ---------------------------------------------------------------------------
-- Server discovery
-- ---------------------------------------------------------------------------

--- Discover the port of a running opencode server.
--- Uses pgrep to find an `opencode --port N` process, then validates the
--- port by checking GET /session returns a 200-ish response.
---@return integer|nil port
function M.discover_port()
  -- Fast path: pgrep argv scan
  local pgrep_out = vim.fn.systemlist("pgrep -af 'opencode.*--port' 2>/dev/null")
  if vim.v.shell_error ~= 0 or #pgrep_out == 0 then
    -- Fallback: lsof listening sockets for opencode processes
    pgrep_out = vim.fn.systemlist("pgrep -a opencode 2>/dev/null")
  end

  for _, line in ipairs(pgrep_out) do
    local port = line:match("%-%-port%s+(%d+)")
    if port then
      local p = tonumber(port)
      if p and p > 0 and p < 65536 then
        -- Validate the port with a quick GET /session
        local check = vim.fn.system(string.format("curl -sf --max-time 1 http://localhost:%d/session 2>/dev/null", p))
        if vim.v.shell_error == 0 and check ~= "" then
          log.debug("opencode_sse", "discovered port %d", p)
          return p
        end
      end
    end
  end

  log.debug("opencode_sse", "no opencode server found")
  return nil
end

-- ---------------------------------------------------------------------------
-- SSE subscriber
-- ---------------------------------------------------------------------------

--- Parse a single SSE data line and call on_event if it contains a known event.
---@param line string  Raw SSE line (e.g. "data: {...}")
local function handle_line(line)
  if not state.on_event then
    return
  end
  local json_str = line:match("^data:%s*(.+)$")
  if not json_str then
    return
  end
  local ok, decoded = pcall(vim.json.decode, json_str)
  if not ok or type(decoded) ~= "table" then
    return
  end
  local event_type = decoded.type or decoded.event
  if event_type then
    local ok2, err = pcall(state.on_event, event_type, decoded)
    if not ok2 then
      log.warn("opencode_sse", "on_event callback error: %s", tostring(err))
    end
  end
end

local function start_curl(port)
  local url = string.format("http://localhost:%d/event", port)
  log.debug("opencode_sse", "subscribing to %s", url)
  local buf = ""
  state.job_id = vim.fn.jobstart({ "curl", "-N", "-s", "--no-buffer", url }, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        buf = buf .. chunk
        -- SSE events are delimited by double newlines; process complete lines
        while true do
          local nl = buf:find("\n")
          if not nl then
            break
          end
          local line = buf:sub(1, nl - 1)
          buf = buf:sub(nl + 1)
          if line ~= "" then
            handle_line(line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      state.job_id = nil
      if code ~= 0 and state.retries < MAX_RETRIES then
        state.retries = state.retries + 1
        log.debug("opencode_sse", "curl exited (code=%d), retry %d/%d", code, state.retries, MAX_RETRIES)
        state.retry_timer = vim.defer_fn(function()
          state.retry_timer = nil
          if state.on_event then
            start_curl(port)
          end
        end, RETRY_DELAY_MS)
      else
        log.debug("opencode_sse", "curl exited (code=%d), not retrying", code)
        state.on_event = nil
      end
    end,
  })
  if state.job_id <= 0 then
    log.warn("opencode_sse", "failed to start curl job")
    state.job_id = nil
  end
end

--- Subscribe to the opencode SSE stream.
---@param port integer  opencode HTTP server port
---@param on_event fun(event_type: string, data: table)  Called for each event
function M.subscribe(port, on_event)
  if state.job_id then
    M.unsubscribe()
  end
  state.port = port
  state.on_event = on_event
  state.retries = 0
  start_curl(port)
end

--- Unsubscribe and stop the curl job.
function M.unsubscribe()
  state.on_event = nil
  if state.retry_timer then
    pcall(vim.fn.timer_stop, state.retry_timer)
    state.retry_timer = nil
  end
  if state.job_id then
    pcall(vim.fn.jobstop, state.job_id)
    state.job_id = nil
  end
  state.port = nil
  state.retries = 0
end

--- Whether a subscription is currently active.
---@return boolean
function M.is_subscribed()
  return state.job_id ~= nil and state.job_id > 0
end

--- Return the currently connected port, or nil.
---@return integer|nil
function M.port()
  return state.port
end

--- Reset all state (for testing).
function M._reset()
  M.unsubscribe()
end

return M
