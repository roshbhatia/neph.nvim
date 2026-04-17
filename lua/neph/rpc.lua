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
  ["tools.status"] = function(_)
    local agents = require("neph.internal.agents").get_all()
    local root = require("neph.internal.tools")._plugin_root()
    return require("neph.internal.tools").status(root, agents)
  end,
  ["tools.install"] = function(p)
    local agents = require("neph.internal.agents").get_all()
    local root = require("neph.internal.tools")._plugin_root()
    for _, agent in ipairs(agents) do
      if agent.name == p.name then
        require("neph.internal.tools").install_agent(root, agent)
        return { ok = true }
      end
    end
    return { ok = false, error = { code = "NOT_FOUND", message = p.name } }
  end,
  ["tools.install_all"] = function(_)
    local agents = require("neph.internal.agents").get_all()
    local root = require("neph.internal.tools")._plugin_root()
    for _, agent in ipairs(agents) do
      require("neph.internal.tools").install_agent(root, agent)
    end
    return { ok = true }
  end,
  ["tools.uninstall"] = function(p)
    local agents = require("neph.internal.agents").get_all()
    for _, agent in ipairs(agents) do
      if agent.name == p.name and agent.tools then
        for _, spec in ipairs(agent.tools) do
          if spec.type == "symlink" then
            local dst = vim.fn.expand(spec.dst)
            local stat = vim.uv.fs_lstat(dst)
            if stat then
              os.remove(dst)
            end
          end
        end
        return { ok = true }
      end
    end
    return { ok = false, error = { code = "NOT_FOUND", message = p.name } }
  end,
  ["tools.preview"] = function(_)
    local agents = require("neph.internal.agents").get_all()
    local root = require("neph.internal.tools")._plugin_root()
    return require("neph.internal.tools").preview(root, agents)
  end,
  -- Review control handlers — allow CLI callers to drive a live review session.
  ["review.status"] = function(_)
    local review = require("neph.api.review")
    local ar = review._active_review()
    if not ar then
      return { active = false }
    end
    local tally = ar.session.get_tally()
    return {
      active = true,
      file = ar.file_path,
      total = ar.session.get_total_hunks(),
      accepted = tally.accepted,
      rejected = tally.rejected,
      undecided = tally.undecided,
    }
  end,
  ["review.accept"] = function(p)
    local review = require("neph.api.review")
    local ar = review._active_review()
    if not ar then
      return { ok = false, error = "No active review" }
    end
    local idx = p.idx
    if not idx then
      idx = ar.session.next_undecided(1)
    end
    if not idx then
      return { ok = false, error = "No undecided hunks" }
    end
    local ok = ar.session.accept_at(idx)
    if not ok then
      return { ok = false, error = "Invalid hunk index: " .. tostring(idx) }
    end
    if ar.ui_state.refresh then
      ar.ui_state.refresh()
    end
    local next_idx = ar.session.next_undecided(idx + 1)
    return { ok = true, idx = idx, next = next_idx }
  end,
  ["review.reject"] = function(p)
    local review = require("neph.api.review")
    local ar = review._active_review()
    if not ar then
      return { ok = false, error = "No active review" }
    end
    local idx = p.idx
    if not idx then
      idx = ar.session.next_undecided(1)
    end
    if not idx then
      return { ok = false, error = "No undecided hunks" }
    end
    local ok = ar.session.reject_at(idx, p.reason)
    if not ok then
      return { ok = false, error = "Invalid hunk index: " .. tostring(idx) }
    end
    if ar.ui_state.refresh then
      ar.ui_state.refresh()
    end
    local next_idx = ar.session.next_undecided(idx + 1)
    return { ok = true, idx = idx, next = next_idx }
  end,
  ["review.accept_all"] = function(_)
    local review = require("neph.api.review")
    local ar = review._active_review()
    if not ar then
      return { ok = false, error = "No active review" }
    end
    local tally_before = ar.session.get_tally()
    ar.session.accept_all_remaining()
    if ar.ui_state.refresh then
      ar.ui_state.refresh()
    end
    return { ok = true, count = tally_before.undecided }
  end,
  ["review.reject_all"] = function(p)
    local review = require("neph.api.review")
    local ar = review._active_review()
    if not ar then
      return { ok = false, error = "No active review" }
    end
    local tally_before = ar.session.get_tally()
    ar.session.reject_all_remaining(p.reason)
    if ar.ui_state.refresh then
      ar.ui_state.refresh()
    end
    return { ok = true, count = tally_before.undecided }
  end,
  ["review.submit"] = function(_)
    local review = require("neph.api.review")
    local ar = review._active_review()
    if not ar then
      return { ok = false, error = "No active review" }
    end
    if ar.ui_state.finalize then
      -- THEORETICAL: vim.schedule defers finalize to the next event-loop tick.
      -- If the user closes the tab (via 'q') between this RPC returning and the
      -- scheduled callback firing, do_finalize()'s `if finalized then return end`
      -- guard prevents a double-finalize.  No real bug; documented for clarity.
      vim.schedule(function()
        ar.ui_state.finalize()
      end)
    else
      return { ok = false, error = "finalize not available" }
    end
    return { ok = true }
  end,
  ["review.next"] = function(_)
    local review = require("neph.api.review")
    local ar = review._active_review()
    if not ar then
      return { ok = false, error = "No active review" }
    end
    local next_idx = ar.session.next_undecided(1)
    if not next_idx then
      return { ok = false, error = "No undecided hunks" }
    end
    if ar.ui_state.jump_to_hunk then
      ar.ui_state.jump_to_hunk(next_idx)
    end
    if ar.ui_state.refresh then
      ar.ui_state.refresh()
    end
    return { ok = true, idx = next_idx }
  end,
}

---@class neph.RpcError
---@field code    string  Machine-readable error code (e.g. "METHOD_NOT_FOUND", "INTERNAL")
---@field message string  Human-readable error description or stack trace

---@class neph.RpcResponse
---@field ok     boolean       True on success
---@field result any?          Handler return value (only present when ok = true)
---@field error  neph.RpcError? Error details (only present when ok = false)

--- Dispatch an RPC method call to the registered handler.
--- Always returns an RpcResponse — never throws. Handler errors are caught and
--- returned as an INTERNAL error response with a truncated traceback.
---@param method string  Dot-separated method name (e.g. "review.open")
---@param params table?  Arbitrary parameters forwarded to the handler
---@return neph.RpcResponse
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
