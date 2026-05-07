---@mod neph.log Debug logging
---@brief [[
--- Lightweight debug logger that appends to /tmp/neph-debug-<pid>.log.
--- Each line is flushed on write (no buffering) so the log survives even a
--- hard freeze / SIGKILL. WARN always writes; DEBUG is gated behind
--- `vim.g.neph_debug` (set explicitly) or `NEPH_DEBUG=1` in the environment.
---@brief ]]

local M = {}

local LOG_PATH = "/tmp/neph-debug-" .. vim.fn.getpid() .. ".log"

--- Initialize debug-mode from env if not already set. Called once from
--- `neph.setup`. Idempotent.
function M.init_from_env()
  if vim.g.neph_debug == nil and vim.env and vim.env.NEPH_DEBUG == "1" then
    vim.g.neph_debug = true
  end
end

---@param module string  Short module name (e.g. "session", "rpc")
---@param fmt string     Format string (string.format style)
---@param ... any        Format arguments
function M.warn(module, fmt, ...)
  -- warn always writes regardless of neph_debug so silent failures surface.
  local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  local ts = os.date("%H:%M:%S") .. string.format(".%03d", math.floor(vim.uv.hrtime() / 1e6) % 1000)
  local line = string.format("[%s] [lua] [WARN] [%s] %s\n", ts, module, msg)
  local f = io.open(M.LOG_PATH, "a")
  if f then
    f:write(line)
    f:close()
  end
end

---@param module string  Short module name (e.g. "session", "rpc")
---@param fmt string     Format string (string.format style)
---@param ... any        Format arguments
function M.debug(module, fmt, ...)
  if not vim.g.neph_debug then
    return
  end
  local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  local ts = os.date("%H:%M:%S") .. string.format(".%03d", math.floor(vim.uv.hrtime() / 1e6) % 1000)
  local line = string.format("[%s] [lua] [%s] %s\n", ts, module, msg)
  local f = io.open(M.LOG_PATH, "a")
  if f then
    f:write(line)
    f:close()
  end
end

---@param path? string  Override log path (for testing)
function M.truncate(path)
  local f = io.open(path or M.LOG_PATH, "w")
  if f then
    f:close()
  end
end

M.LOG_PATH = LOG_PATH

return M
