---@mod neph.rpc RPC dispatch facade
---@brief [[
--- Single entry point for all external RPC calls into neph.nvim.
--- External code calls `require("neph.rpc").request(method, params)`.
--- Routes to the appropriate `lua/neph/api/` module.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

local dispatch = {
  ["review.open"] = function(p)
    return require("neph.api.review").open(p)
  end,
  ["status.set"] = function(p)
    return require("neph.api.status").set(p)
  end,
  ["status.unset"] = function(p)
    return require("neph.api.status").unset(p)
  end,
  ["status.get"] = function(p)
    return require("neph.api.status").get(p)
  end,
  ["buffers.check"] = function(p)
    return require("neph.api.buffers").checktime(p)
  end,
  ["tab.close"] = function(p)
    return require("neph.api.buffers").close_tab(p)
  end,
  ["ui.select"] = function(p)
    return require("neph.api.ui").select(p)
  end,
  ["ui.input"] = function(p)
    return require("neph.api.ui").input(p)
  end,
  ["ui.notify"] = function(p)
    return require("neph.api.ui").notify(p)
  end,
}

function M.request(method, params)
  log.debug("rpc", "dispatch: %s params=%s", method, vim.inspect(params, { newline = " ", indent = "" }))
  local handler = dispatch[method]
  if not handler then
    log.debug("rpc", "dispatch: METHOD_NOT_FOUND %s", method)
    return { ok = false, error = { code = "METHOD_NOT_FOUND", message = method } }
  end
  local ok, result = pcall(handler, params or {})
  if not ok then
    local trace = debug.traceback(tostring(result), 2)
    if #trace > 500 then
      trace = trace:sub(1, 500)
    end
    log.debug("rpc", "dispatch: INTERNAL error %s: %s", method, trace)
    return { ok = false, error = { code = "INTERNAL", message = trace } }
  end
  log.debug("rpc", "dispatch: %s result=%s", method, vim.inspect(result, { newline = " ", indent = "" }))
  return { ok = true, result = result }
end

return M
