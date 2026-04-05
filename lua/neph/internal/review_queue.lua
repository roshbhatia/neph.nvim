---@mod neph.internal.review_queue Sequential review queue
---@brief [[
--- FIFO queue ensuring only one review is active at a time.
--- When an agent writes multiple files rapidly, reviews are queued
--- and presented sequentially.
---@brief ]]

local M = {}

local log = require("neph.internal.log")

local MAX_QUEUE_SIZE = 50

---@class neph.ReviewRequest
---@field request_id string
---@field result_path string
---@field channel_id integer
---@field path string
---@field content string
---@field agent? string
---@field mode? string  "pre_write" | "post_write"

---@type neph.ReviewRequest[]
local queue = {}

---@type neph.ReviewRequest|nil
local active = nil

local pending_notify_batch = {}
local notify_timer = nil

---@type fun(params: neph.ReviewRequest)|nil
local open_fn = nil

---@type table<string, number>  path → hrtime of last completed review
local recently_reviewed = {}

--- Batch a queued review into the pending notification and schedule the 400ms
--- debounce timer if not already scheduled.
---@param params neph.ReviewRequest
local function batch_notify(params)
  local config = require("neph.config").current
  local review_cfg = type(config.review) == "table" and config.review or {}
  if review_cfg.pending_notify == false then
    return
  end
  table.insert(pending_notify_batch, params)
  if not notify_timer then
    notify_timer = vim.defer_fn(function()
      notify_timer = nil
      local batch = pending_notify_batch
      pending_notify_batch = {}
      if #batch == 0 then
        return
      end
      local agents_seen = {}
      local agent_list = {}
      for _, p in ipairs(batch) do
        local a = p.agent or "unknown"
        if not agents_seen[a] then
          agents_seen[a] = true
          table.insert(agent_list, a)
        end
      end
      local agent_str = "(" .. table.concat(agent_list, ", ") .. ")"
      vim.notify(
        string.format("Neph: %d review%s queued %s", #batch, #batch == 1 and "" or "s", agent_str),
        vim.log.levels.INFO
      )
    end, 400)
  end
end

---@param fn fun(params: neph.ReviewRequest)
function M.set_open_fn(fn)
  open_fn = fn
end

---@param params neph.ReviewRequest
function M.enqueue(params)
  if not open_fn then
    vim.notify("Neph: review UI not initialised (set_open_fn not called)", vim.log.levels.WARN)
    return
  end

  local gate = require("neph.internal.gate")
  local gate_state = gate.get()

  if gate_state == "hold" then
    table.insert(queue, params)
    vim.notify(string.format("Neph: review held — %d pending", #queue), vim.log.levels.INFO)
    return
  elseif gate_state == "bypass" then
    local ok, review = pcall(require, "neph.api.review")
    if ok and review._bypass_accept then
      review._bypass_accept(params)
    end
    return
  end

  if not active then
    active = params
    log.debug("review_queue", "opening immediately: %s", params.path)
    -- vim.schedule so open_fn is safe even when enqueue is called from a
    -- libuv fast-event context (e.g. fs_watcher callbacks).  The snapshot
    -- guard prevents a double-open if cancel_path / on_complete fires before
    -- the scheduled callback runs.
    local snapshot = active
    vim.schedule(function()
      if active == snapshot and open_fn then
        open_fn(active)
      end
    end)
  else
    if #queue >= MAX_QUEUE_SIZE then
      local dropped = table.remove(queue, 1)
      log.debug("review_queue", "queue full (%d), dropping oldest: %s", MAX_QUEUE_SIZE, dropped.path)
      vim.notify(
        string.format("Neph: review queue full — dropped oldest review: %s", vim.fn.fnamemodify(dropped.path, ":.")),
        vim.log.levels.WARN
      )
    end
    table.insert(queue, params)
    log.debug("review_queue", "queued: %s (pending=%d)", params.path, #queue)

    batch_notify(params)
  end
end

---@param request_id string
function M.on_complete(request_id)
  if active and active.request_id == request_id then
    log.debug("review_queue", "completed: %s", active.path)
    active = nil
  end

  -- Pop next from queue
  if #queue > 0 then
    local next_review = table.remove(queue, 1)
    if next_review then
      active = next_review
      log.debug("review_queue", "opening next: %s (remaining=%d)", active.path, #queue)
      if open_fn then
        local snapshot = active
        vim.schedule(function()
          -- Guard: only open if active hasn't been replaced by cancel_path
          -- or another on_complete in the meantime.
          if active == snapshot then
            open_fn(active)
          end
        end)
      end
    end
  end
end

---@return integer
function M.count()
  return #queue
end

---@return neph.ReviewRequest|nil
function M.get_active()
  if active == nil then
    return nil
  end
  return vim.deepcopy(active)
end

--- Mark a path as recently reviewed (suppresses fs_watcher duplicates).
---@param path string
function M.mark_reviewed(path)
  recently_reviewed[path] = vim.uv.hrtime()
end

--- Returns true if a path was reviewed within the last ttl_ms milliseconds.
---@param path string
---@param ttl_ms? number  default 5000
---@return boolean
function M.was_recently_reviewed(path, ttl_ms)
  local t = recently_reviewed[path]
  if not t then
    return false
  end
  local now = vim.uv.hrtime()
  -- Guard against the (practically impossible) uint64 wrap: treat any
  -- case where now < t as "not recently reviewed" rather than a negative
  -- elapsed time which would divide to a huge positive value.
  if now < t then
    return false
  end
  local elapsed_ms = (now - t) / 1e6
  return elapsed_ms < (ttl_ms or 5000)
end

---@return integer  total reviews (active + queued)
function M.total()
  return (active and 1 or 0) + #queue
end

---@param agent_name string
function M.clear_agent(agent_name)
  -- Remove queued reviews for this agent
  local new_queue = {}
  for _, req in ipairs(queue) do
    if req.agent ~= agent_name then
      table.insert(new_queue, req)
    end
  end
  local removed = #queue - #new_queue
  queue = new_queue

  -- Cancel active review if it belongs to this agent
  local cancelled_active = false
  if active and active.agent == agent_name then
    log.debug("review_queue", "cancelling active review for killed agent: %s", agent_name)
    active = nil
    cancelled_active = true
  end

  if removed > 0 or cancelled_active then
    log.debug(
      "review_queue",
      "cleared %d queued + %s active for agent %s",
      removed,
      cancelled_active and "1" or "0",
      agent_name
    )
  end

  -- If we cancelled the active review, open next
  if cancelled_active and #queue > 0 then
    active = table.remove(queue, 1)
    if open_fn then
      local snapshot = active
      vim.schedule(function()
        if active == snapshot then
          open_fn(active)
        end
      end)
    end
  end
end

---@param path string
---@return boolean
function M.is_in_review(path)
  if active and active.path == path then
    return true
  end
  for _, req in ipairs(queue) do
    if req.path == path then
      return true
    end
  end
  return false
end

--- Cancel a queued or active review by file path.
---@param path string
function M.cancel_path(path)
  -- Remove from queue
  local new_queue = {}
  for _, req in ipairs(queue) do
    if req.path ~= path then
      table.insert(new_queue, req)
    end
  end
  queue = new_queue

  -- Cancel active review if it matches
  if active and active.path == path then
    local cancelled = active
    log.debug("review_queue", "cancelling active review for path: %s", path)
    active = nil

    -- Notify the CLI reviewer so it does not hang waiting for a result.
    -- Attempt to write a cancellation result via the review API if available.
    local ok, review_api = pcall(require, "neph.api.review")
    if ok and review_api.write_result then
      local envelope = {
        schema = "review/v1",
        decision = "reject",
        content = cancelled.content or "",
        hunks = {},
        reason = "cancelled",
      }
      review_api.write_result(cancelled.result_path, cancelled.channel_id, cancelled.request_id, envelope)
    end

    -- Open next queued review
    if #queue > 0 then
      active = table.remove(queue, 1)
      if open_fn then
        local snapshot = active
        vim.schedule(function()
          if active == snapshot then
            open_fn(active)
          end
        end)
      end
    end
  end
end

--- Enqueue a review at the front of the queue (user-initiated reviews).
--- If nothing is active, opens immediately. Otherwise jumps ahead of any
--- pending agent reviews so the user sees their file next.
---@param params neph.ReviewRequest
function M.enqueue_front(params)
  if not open_fn then
    vim.notify("Neph: review UI not initialised (set_open_fn not called)", vim.log.levels.WARN)
    return
  end

  local gate = require("neph.internal.gate")
  local gate_state = gate.get()

  if gate_state == "hold" then
    table.insert(queue, 1, params)
    vim.notify(string.format("Neph: review held — %d pending", #queue), vim.log.levels.INFO)
    return
  elseif gate_state == "bypass" then
    local ok, review = pcall(require, "neph.api.review")
    if ok and review._bypass_accept then
      review._bypass_accept(params)
    end
    return
  end

  if not active then
    active = params
    log.debug("review_queue", "opening immediately (front): %s", params.path)
    local snapshot = active
    vim.schedule(function()
      if active == snapshot and open_fn then
        open_fn(active)
      end
    end)
  else
    table.insert(queue, 1, params)
    log.debug("review_queue", "queued at front: %s (pending=%d)", params.path, #queue)
    batch_notify(params)
  end
end

--- Drain the held queue after a gate release.
--- Triggers open_fn for the head item if nothing is currently active.
function M.drain()
  if active or not open_fn then
    return
  end
  local next_review = table.remove(queue, 1)
  if next_review then
    active = next_review
    if open_fn then
      local snapshot = active
      vim.schedule(function()
        if active == snapshot then
          open_fn(active)
        end
      end)
    end
  end
end

--- Reset all state (for testing)
function M._reset()
  queue = {}
  active = nil
  open_fn = nil
  recently_reviewed = {}
  pending_notify_batch = {}
  if notify_timer then
    -- vim.defer_fn timers can't be cancelled directly, but we clear the batch
    -- so the timer fires and does nothing
    pending_notify_batch = {}
    notify_timer = nil
  end
end

--- Returns a shallow copy of the pending queue (not the live table).
---@return neph.ReviewRequest[]
function M.get_queue()
  return vim.deepcopy(queue)
end

--- Reject all pending (queued, not-yet-active) reviews.
--- Writes a reject envelope for each so CLI callers are not left hanging.
--- Called from VimLeavePre so callers receive a response before exit.
---@param reason string  Human-readable rejection reason
function M.reject_all_pending(reason)
  if #queue == 0 then
    return
  end

  local pending = queue
  queue = {}

  local ok, review_api = pcall(require, "neph.api.review")

  for _, req in ipairs(pending) do
    log.debug("review_queue", "reject_all_pending: %s (%s)", req.path, reason)
    if ok and review_api.write_result then
      local envelope = {
        schema = "review/v1",
        decision = "reject",
        content = req.content or "",
        hunks = {},
        reason = reason,
      }
      pcall(review_api.write_result, req.result_path, req.channel_id, req.request_id, envelope)
    end
  end
end

return M
