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

---@type fun(params: neph.ReviewRequest)|nil
local open_fn = nil

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
    if not open_fn then
      vim.notify("neph: review queue: no open function set — review dropped", vim.log.levels.WARN)
      active = nil
      return
    end
    open_fn(params)
  else
    if #queue >= MAX_QUEUE_SIZE then
      log.debug("review_queue", "queue full (%d), dropping oldest: %s", MAX_QUEUE_SIZE, queue[1].path)
      table.remove(queue, 1)
    end
    table.insert(queue, params)
    log.debug("review_queue", "queued: %s (pending=%d)", params.path, #queue)

    -- Show notification for queued review
    local config = require("neph.config").current
    local review_cfg = type(config.review) == "table" and config.review or {}
    if review_cfg.pending_notify ~= false then
      local rel = vim.fn.fnamemodify(params.path, ":.")
      local agent_str = params.agent and (" (" .. params.agent .. ")") or ""
      vim.notify(string.format("Review queued: %s%s — %d pending", rel, agent_str, #queue), vim.log.levels.INFO)
    end
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
        vim.schedule(function()
          if active then
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
  return active
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
      vim.schedule(function()
        open_fn(active)
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
    log.debug("review_queue", "cancelling active review for path: %s", path)
    active = nil
    -- Open next queued review
    if #queue > 0 then
      active = table.remove(queue, 1)
      if open_fn then
        vim.schedule(function()
          open_fn(active)
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
    open_fn(params)
  else
    table.insert(queue, 1, params)
    log.debug("review_queue", "queued at front: %s (pending=%d)", params.path, #queue)
    local config = require("neph.config").current
    local review_cfg = type(config.review) == "table" and config.review or {}
    if review_cfg.pending_notify ~= false then
      vim.notify(
        string.format("Review queued (next): %s — %d pending", vim.fn.fnamemodify(params.path, ":."), #queue),
        vim.log.levels.INFO
      )
    end
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
    vim.schedule(function()
      if active then
        open_fn(active)
      end
    end)
  end
end

--- Reset all state (for testing)
function M._reset()
  queue = {}
  active = nil
  open_fn = nil
end

return M
