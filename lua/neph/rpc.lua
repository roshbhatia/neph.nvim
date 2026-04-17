---@mod neph.rpc RPC dispatch facade
---@brief [[
--- Single entry point for all external RPC calls into neph.nvim.
--- External code calls `require("neph.rpc").request(method, params)`.
--- Routes to the appropriate `lua/neph/api/` module.
---
--- Error envelope contract (Pass 6):
---   Every call returns a table with exactly one of two shapes:
---     { ok = true,  result = <handler-return> }
---     { ok = false, error  = { code = string, message = string } }
---
--- Outer error codes produced by the dispatcher itself:
---   "METHOD_NOT_FOUND"  -- no handler registered for the requested method
---   "INVALID_PARAMS"    -- params argument is not a table (and was not nil)
---   "INTERNAL"          -- the handler threw a Lua error (pcall caught it)
---                          or returned a non-serializable value
---
--- Inner error codes are handler-defined (e.g. "INVALID_PARAMS",
--- "CHECKTIME_FAILED", "NOT_FOUND") and appear inside result.error when
--- the handler returns { ok = false, error = ... } cleanly.
---
--- Debug logging (Pass 7):
---   Set vim.g.neph_debug = 1 (or export NEPH_DEBUG=1 before Neovim starts)
---   to enable per-dispatch log lines in /tmp/neph-debug-<pid>.log.
---
--- Lazy require contract (Pass 8):
---   Every handler MUST use require() inside its closure body so that api/
---   modules are loaded on first use, not at plugin startup.  Do NOT hoist
---   requires to the top of this file -- hoisting causes load-order failures
---   when api/ modules depend on setup() having run.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

-- Pass 7: Bridge NEPH_DEBUG environment variable to vim.g.neph_debug.
-- This allows callers to set NEPH_DEBUG=1 before launching Neovim without
-- needing to modify init.lua.  Only set it when the var is not already set
-- so that user's init.lua always takes precedence.
if vim.g.neph_debug == nil and os.getenv("NEPH_DEBUG") == "1" then
  vim.g.neph_debug = 1
end

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

-- Pass 5: Walk a value and verify it contains no non-serializable Lua types
-- (functions, userdata, threads).  Returns true when safe to JSON-encode,
-- false + offending type string otherwise.
---@param value any
---@param depth? number  Internal recursion depth guard (max 32)
---@return boolean ok
---@return string? bad_type
local function is_serializable(value, depth)
  depth = depth or 0
  if depth > 32 then
    return false, "recursion_limit"
  end
  local t = type(value)
  if t == "function" or t == "userdata" or t == "thread" then
    return false, t
  end
  if t == "table" then
    for k, v in pairs(value) do
      local ok, bad = is_serializable(k, depth + 1)
      if not ok then
        return false, bad
      end
      ok, bad = is_serializable(v, depth + 1)
      if not ok then
        return false, bad
      end
    end
  end
  return true
end

-- Pass 1: Maximum bytes echoed back from an unknown method name in the error
-- message.  Prevents a pathologically long name from inflating the response.
local MAX_METHOD_ECHO = 200

---Dispatch an RPC call to the registered handler.
---@param method string  The dot-separated method name (e.g. "status.set").
---@param params table?  Key/value parameters for the handler.  nil is treated
---                      as an empty table.  Non-table values are rejected with
---                      an INVALID_PARAMS error before reaching any handler.
---@return table  Always a table.  Success: `{ ok=true, result=any }`.
---               Failure: `{ ok=false, error={code=string, message=string} }`.
function M.request(method, params)
  log.debug("rpc", "dispatch: %s params=%s", method, vim.inspect(params, { newline = " ", indent = "" }))

  -- Pass 1: unknown method -> structured error with truncated echo.
  local handler = dispatch[method]
  if not handler then
    local echo = type(method) == "string" and method:sub(1, MAX_METHOD_ECHO) or tostring(method):sub(1, MAX_METHOD_ECHO)
    log.debug("rpc", "dispatch: METHOD_NOT_FOUND %s", method)
    return { ok = false, error = { code = "METHOD_NOT_FOUND", message = echo } }
  end

  -- Pass 3: reject non-table params before they reach any handler.
  -- nil -> {} is safe (many handlers treat missing params as "no arguments").
  -- A non-table scalar here is a caller bug and gets a clean INVALID_PARAMS
  -- instead of an opaque INTERNAL traceback.
  if params ~= nil and type(params) ~= "table" then
    log.debug("rpc", "dispatch: INVALID_PARAMS %s params type=%s", method, type(params))
    return {
      ok = false,
      error = { code = "INVALID_PARAMS", message = "params must be a table, got " .. type(params) },
    }
  end

  -- Pass 2: wrap every handler in pcall so no handler can crash Neovim.
  local ok, result = pcall(handler, params or {})
  if not ok then
    local trace = debug.traceback(tostring(result), 2)
    if #trace > 500 then
      trace = trace:sub(1, 500)
    end
    log.debug("rpc", "dispatch: INTERNAL error %s: %s", method, trace)
    return { ok = false, error = { code = "INTERNAL", message = trace } }
  end

  -- Pass 5: verify the result is JSON-serializable before returning it.
  -- Catches handlers that accidentally return a function or userdata value,
  -- which would produce garbage on the msgpack wire.
  local serial_ok, bad_type = is_serializable(result)
  if not serial_ok then
    local msg = string.format("handler '%s' returned non-serializable value (%s)", method, tostring(bad_type))
    log.warn("rpc", msg)
    return { ok = false, error = { code = "INTERNAL", message = msg } }
  end

  log.debug("rpc", "dispatch: %s result=%s", method, vim.inspect(result, { newline = " ", indent = "" }))
  return { ok = true, result = result }
end

return M
