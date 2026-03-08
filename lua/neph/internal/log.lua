---@mod neph.log Debug logging
---@brief [[
--- Lightweight debug logger that appends to /tmp/neph-debug.log.
--- Gated behind vim.g.neph_debug — no-op when disabled.
---@brief ]]

local M = {}

local LOG_PATH = "/tmp/neph-debug.log"

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
