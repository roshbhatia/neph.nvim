---@mod neph.internal.watchdog Slow-callback watchdog
---@brief [[
--- Wraps callbacks in a hrtime measurement and logs at WARN level when any
--- single invocation exceeds a threshold. Cheap to leave on in normal
--- operation; gives a breadcrumb trail when something hangs the event loop.
---
--- Off by default. Enable via `NEPH_WATCHDOG=1` in the environment or
--- `setup({ watchdog = { enable = true, threshold_ms = 200 } })`.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

---@type {enabled: boolean, threshold_ms: number}
local state = {
  enabled = false,
  threshold_ms = 200,
}

--- Enable or disable the watchdog. Reads `NEPH_WATCHDOG=1` from the env if
--- *opts* is not provided.
---@param opts? {enable?: boolean, threshold_ms?: number}
function M.setup(opts)
  opts = opts or {}
  if opts.enable ~= nil then
    state.enabled = opts.enable == true
  else
    state.enabled = vim.env.NEPH_WATCHDOG == "1"
  end
  if type(opts.threshold_ms) == "number" and opts.threshold_ms > 0 then
    state.threshold_ms = opts.threshold_ms
  end
end

--- Wrap *fn* so that invocations exceeding the configured threshold log a
--- WARN line. Pass-through for return values and errors. When watchdog is
--- disabled, returns *fn* unwrapped (zero overhead).
---@generic F: function
---@param name string  Identifier surfaced in WARN logs (keep it short)
---@param fn F
---@return F
function M.wrap(name, fn)
  return function(...)
    if not state.enabled then
      return fn(...)
    end
    local t0 = vim.uv.hrtime()
    local ok, ret = pcall(fn, ...)
    local elapsed_ms = (vim.uv.hrtime() - t0) / 1e6
    if elapsed_ms > state.threshold_ms then
      log.warn("watchdog", "%s took %.1fms (threshold %dms)", name, elapsed_ms, state.threshold_ms)
    end
    if not ok then
      error(ret)
    end
    return ret
  end
end

--- Reset state for tests.
function M._reset()
  state.enabled = false
  state.threshold_ms = 200
end

--- Inspect state for tests.
function M._state()
  return { enabled = state.enabled, threshold_ms = state.threshold_ms }
end

return M
