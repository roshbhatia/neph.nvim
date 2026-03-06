local M = {}

local dispatch = {
  ["review.open"]   = function(p) return require("neph.api.review").open(p) end,
  ["status.set"]    = function(p) return require("neph.api.status").set(p) end,
  ["status.unset"]  = function(p) return require("neph.api.status").unset(p) end,
  ["buffers.check"] = function(p) return require("neph.api.buffers").checktime(p) end,
  ["tab.close"]     = function(p) return require("neph.api.buffers").close_tab(p) end,
}

function M.request(method, params)
  local handler = dispatch[method]
  if not handler then
    return { ok = false, error = { code = "METHOD_NOT_FOUND", message = method } }
  end
  local ok, result = pcall(handler, params or {})
  if not ok then
    return { ok = false, error = { code = "INTERNAL", message = result } }
  end
  return { ok = true, result = result }
end

return M
