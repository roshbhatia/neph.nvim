---@diagnostic disable: undefined-global
-- tests/internal/review_queue_edge_spec.lua
-- Edge-case and regression tests for neph.internal.review_queue.
-- Each test group corresponds to a specific correctness issue that was audited
-- and fixed in the module.

local rq

local function make_req(id, path, agent)
  return {
    request_id = id or ("req-" .. tostring(math.random(10000))),
    result_path = "/tmp/edge-result-" .. (id or "x") .. ".json",
    channel_id = 1, -- non-zero so write_result would attempt rpcnotify
    path = path or "/tmp/edge.lua",
    content = "content",
    agent = agent or "test-agent",
    mode = "pre_write",
  }
end

-- Flush pending vim.schedule callbacks so synchronous assertions work after enqueue.
local function flush()
  vim.wait(50, function()
    return false
  end)
end

-- ---------------------------------------------------------------------------
-- Setup helpers
--
-- NOTE: before_each/after_each MUST be inside a describe block. When they sit
-- at file scope, plenary's busted runner crashes (`bad argument to insert`)
-- but the nvim subprocess never exits — leaving a zombie nvim process per
-- run that accumulates over time and starves system resources, manifesting
-- as new nvim instances hanging in unrelated directories. Wrap everything
-- in a single outer describe to keep these hooks scoped properly.
-- ---------------------------------------------------------------------------

describe("review_queue edge cases", function()
  before_each(function()
    package.loaded["neph.internal.review_queue"] = nil
    package.loaded["neph.internal.gate"] = nil
    rq = require("neph.internal.review_queue")
    -- Reset gate to "normal" so open_fn is invoked (bypass would short-circuit)
    require("neph.internal.gate").set("normal")
  end)

  after_each(function()
    if rq then
      rq._reset()
    end
    pcall(function()
      require("neph.internal.gate").set("normal")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 1 & 2: open_fn called via vim.schedule (fast-event safety)
  -- ---------------------------------------------------------------------------

  describe("review_queue: enqueue schedules open_fn via vim.schedule", function()
    it("open_fn is NOT called synchronously before flush", function()
      local calls = {}
      rq.set_open_fn(function(p)
        table.insert(calls, p.request_id)
      end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      -- Before flushing the scheduler, open_fn must not have fired yet
      assert.are.equal(0, #calls, "open_fn must not fire synchronously (fast-event safety)")
    end)

    it("open_fn IS called after flush", function()
      local calls = {}
      rq.set_open_fn(function(p)
        table.insert(calls, p.request_id)
      end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      flush()
      assert.are.equal(1, #calls)
      assert.are.equal("r1", calls[1])
    end)

    it("enqueue_front also defers open_fn via vim.schedule", function()
      local calls = {}
      rq.set_open_fn(function(p)
        table.insert(calls, p.request_id)
      end)
      rq.enqueue_front(make_req("rf1", "/tmp/front.lua"))
      assert.are.equal(0, #calls, "enqueue_front must not call open_fn synchronously")
      flush()
      assert.are.equal(1, #calls)
      assert.are.equal("rf1", calls[1])
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 1 cont.: snapshot guard prevents double-open
  -- ---------------------------------------------------------------------------

  describe("review_queue: snapshot guard prevents double-open race", function()
    it("cancel_path between enqueue and flush suppresses open_fn", function()
      local calls = {}
      rq.set_open_fn(function(p)
        table.insert(calls, p.request_id)
      end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      -- Cancel before the scheduled callback fires
      rq.cancel_path("/tmp/a.lua")
      flush()
      assert.are.equal(0, #calls, "open_fn must be suppressed after cancel_path pre-flush")
      assert.is_nil(rq.get_active())
    end)

    it("on_complete between enqueue and flush for same item suppresses open_fn", function()
      -- Simulate: enqueue sets active=r1 and schedules open; then on_complete("r1")
      -- clears active before the schedule fires.  The snapshot guard must prevent
      -- open_fn from firing for the already-completed item.
      local calls = {}
      rq.set_open_fn(function(p)
        table.insert(calls, p.request_id)
      end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      -- Complete before the scheduled open fires
      rq.on_complete("r1")
      flush()
      assert.are.equal(0, #calls, "open_fn must not fire for an already-completed active item")
      assert.is_nil(rq.get_active())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 3: cancel_path of active review notifies caller (no CLI hang)
  -- ---------------------------------------------------------------------------

  describe("review_queue: cancel_path notifies caller for active review", function()
    it("cancel_path on active review invokes write_result via review API", function()
      -- Stub neph.api.review so we can observe write_result calls without a
      -- real Neovim review session.
      local written = {}
      package.loaded["neph.api.review"] = {
        write_result = function(path, channel_id, request_id, envelope)
          table.insert(written, {
            path = path,
            channel_id = channel_id,
            request_id = request_id,
            envelope = envelope,
          })
        end,
      }

      rq.set_open_fn(function(_) end)
      local req = make_req("cancel-active", "/tmp/cancel.lua")
      rq.enqueue(req)

      -- Active is set synchronously; cancel it
      rq.cancel_path("/tmp/cancel.lua")

      assert.are.equal(1, #written, "write_result should be called once for the cancelled active review")
      assert.are.equal("cancel-active", written[1].request_id)
      assert.are.equal("reject", written[1].envelope.decision)
      assert.are.equal("cancelled", written[1].envelope.reason)

      -- Clean up stub
      package.loaded["neph.api.review"] = nil
    end)

    it("cancel_path of queued (non-active) review does NOT call write_result", function()
      local written = {}
      package.loaded["neph.api.review"] = {
        write_result = function(_, _, request_id, _)
          table.insert(written, request_id)
        end,
      }

      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2-queued", "/tmp/b.lua"))
      -- Cancel the queued item (not active)
      rq.cancel_path("/tmp/b.lua")

      assert.are.equal(0, #written, "write_result must not be called for a queued-only cancellation")

      package.loaded["neph.api.review"] = nil
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 4: get_active() returns deepcopy (consistent with get_queue)
  -- ---------------------------------------------------------------------------

  describe("review_queue: get_active returns deepcopy", function()
    it("mutating the result of get_active does not affect internal active", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))

      local copy = rq.get_active()
      assert.is_not_nil(copy)

      -- Mutate the returned copy
      copy.request_id = "MUTATED"
      copy.path = "/tmp/mutated.lua"

      -- Internal state must be unaffected
      local copy2 = rq.get_active()
      assert.are.equal("r1", copy2.request_id)
      assert.are.equal("/tmp/a.lua", copy2.path)
    end)

    it("get_active returns nil when queue is idle", function()
      assert.is_nil(rq.get_active())
    end)

    it("get_active and get_queue are consistent snapshots after enqueue", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2", "/tmp/b.lua"))

      local active_snap = rq.get_active()
      local queue_snap = rq.get_queue()

      assert.is_not_nil(active_snap)
      assert.are.equal("r1", active_snap.request_id)
      assert.are.equal(1, #queue_snap)
      assert.are.equal("r2", queue_snap[1].request_id)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 5: was_recently_reviewed hrtime guard
  -- ---------------------------------------------------------------------------

  describe("review_queue: was_recently_reviewed hrtime safety", function()
    it("returns false for an unknown path", function()
      assert.is_false(rq.was_recently_reviewed("/tmp/never-seen.lua"))
    end)

    it("returns true immediately after mark_reviewed", function()
      rq.mark_reviewed("/tmp/fresh.lua")
      assert.is_true(rq.was_recently_reviewed("/tmp/fresh.lua", 5000))
    end)

    it("returns false when ttl_ms is 0 (always expired)", function()
      rq.mark_reviewed("/tmp/zero-ttl.lua")
      -- A 0ms TTL means any elapsed time is >= 0, so it should be false
      -- (elapsed_ms >= 0 is always true; 0 < 0 is false)
      assert.is_false(rq.was_recently_reviewed("/tmp/zero-ttl.lua", 0))
    end)

    it("simulated hrtime wrap: if stored t > now, returns false safely", function()
      -- Simulate a stored timestamp in the future (as would happen on wrap)
      -- by directly injecting via mark_reviewed then patching hrtime.
      local orig_hrtime = vim.uv.hrtime
      -- Store a real timestamp
      rq.mark_reviewed("/tmp/wrap.lua")
      -- Now mock hrtime to return a value smaller than what was stored
      vim.uv.hrtime = function()
        return 1 -- very small value, simulating post-wrap
      end
      -- Must return false, not a huge "elapsed" value
      local result = rq.was_recently_reviewed("/tmp/wrap.lua", 5000)
      vim.uv.hrtime = orig_hrtime
      assert.is_false(result, "hrtime wrap must return false, not a spurious 'recently reviewed'")
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 6: batch_notify handles nil agent gracefully
  -- ---------------------------------------------------------------------------

  describe("review_queue: batch_notify nil agent safety", function()
    it("enqueue with nil agent does not error in batch_notify path", function()
      -- batch_notify is triggered when there is an active review and a new one
      -- is queued (so open_fn is not called for the second item).
      -- Stub config to allow pending_notify
      package.loaded["neph.config"] = {
        current = { review = { pending_notify = true } },
      }

      rq.set_open_fn(function(_) end)
      local req_no_agent = {
        request_id = "no-agent",
        result_path = "/tmp/no-agent.json",
        channel_id = 0,
        path = "/tmp/no-agent.lua",
        content = "x",
        agent = nil, -- explicitly nil
      }

      -- Enqueue first to make something active
      rq.enqueue(make_req("r1", "/tmp/a.lua", "existing"))
      -- Second enqueue triggers batch_notify with nil agent
      assert.has_no.errors(function()
        rq.enqueue(req_no_agent)
      end)

      package.loaded["neph.config"] = nil
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 7: _reset + pending notify_timer closure safety
  -- ---------------------------------------------------------------------------

  describe("review_queue: _reset timer closure safety", function()
    it("_reset followed by new enqueue does not double-fire open_fn", function()
      -- Trigger a batch_notify timer, then reset while it is still pending.
      -- After reset, a new enqueue should work correctly without interference
      -- from the old timer's closure.
      package.loaded["neph.config"] = {
        current = { review = { pending_notify = true } },
      }

      local calls = {}
      rq.set_open_fn(function(p)
        table.insert(calls, p.request_id)
      end)

      -- Create an active review so the second enqueue goes to batch_notify
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2", "/tmp/b.lua")) -- queued; triggers notify timer

      -- Reset while timer is pending
      rq._reset()

      -- Start fresh
      local calls2 = {}
      rq.set_open_fn(function(p)
        table.insert(calls2, p.request_id)
      end)
      rq.enqueue(make_req("new1", "/tmp/new.lua"))
      flush()

      -- Only the new enqueue's open_fn should fire; the old timer fires into an
      -- empty pending_notify_batch and does nothing harmful.
      assert.are.equal(1, #calls2)
      assert.are.equal("new1", calls2[1])

      package.loaded["neph.config"] = nil
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 8: enqueue / enqueue_front input validation (nil/empty request_id)
  -- ---------------------------------------------------------------------------

  describe("review_queue: enqueue input validation", function()
    it("enqueue with nil request_id drops the request and does not set active", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue({
        request_id = nil,
        result_path = "/tmp/nil-id.json",
        channel_id = 0,
        path = "/tmp/nil-id.lua",
        content = "x",
        agent = "test-agent",
        mode = "pre_write",
      })
      assert.is_nil(rq.get_active(), "nil request_id must not be enqueued")
      assert.are.equal(0, rq.count())
    end)

    it("enqueue with empty-string request_id drops the request", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue({
        request_id = "",
        result_path = "/tmp/empty-id.json",
        channel_id = 0,
        path = "/tmp/empty-id.lua",
        content = "x",
        agent = "test-agent",
        mode = "pre_write",
      })
      assert.is_nil(rq.get_active(), "empty request_id must not be enqueued")
      assert.are.equal(0, rq.count())
    end)

    it("enqueue_front with nil request_id drops the request", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue_front({
        request_id = nil,
        result_path = "/tmp/nil-front.json",
        channel_id = 0,
        path = "/tmp/nil-front.lua",
        content = "x",
        agent = "test-agent",
        mode = "pre_write",
      })
      assert.is_nil(rq.get_active(), "nil request_id must not be enqueued_front")
      assert.are.equal(0, rq.count())
    end)

    it("enqueue_front with empty-string request_id drops the request", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue_front({
        request_id = "",
        result_path = "/tmp/empty-front.json",
        channel_id = 0,
        path = "/tmp/empty-front.lua",
        content = "x",
        agent = "test-agent",
        mode = "pre_write",
      })
      assert.is_nil(rq.get_active(), "empty request_id must not be enqueued_front")
      assert.are.equal(0, rq.count())
    end)

    it("valid enqueue after rejected nil-id enqueue works correctly", function()
      local calls = {}
      rq.set_open_fn(function(p)
        table.insert(calls, p.request_id)
      end)
      -- Invalid first, valid second
      rq.enqueue({ request_id = nil, path = "/tmp/bad.lua", content = "", channel_id = 0 })
      rq.enqueue(make_req("valid-after-nil", "/tmp/good.lua"))
      flush()
      assert.are.equal(1, #calls)
      assert.are.equal("valid-after-nil", calls[1])
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 9: on_complete contract — unknown/duplicate/nil request_id is no-op
  -- ---------------------------------------------------------------------------

  describe("review_queue: on_complete contract", function()
    it("on_complete with nil request_id is a no-op (does not clear active)", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      -- r1 is now active; call on_complete with nil — must not clear it
      rq.on_complete(nil) -- luacheck: ignore
      local active = rq.get_active()
      assert.is_not_nil(active, "active must remain after on_complete(nil)")
      assert.are.equal("r1", active.request_id)
    end)

    it("on_complete with empty string is a no-op (does not clear active)", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.on_complete("")
      local active = rq.get_active()
      assert.is_not_nil(active)
      assert.are.equal("r1", active.request_id)
    end)

    it("on_complete with unknown request_id is a no-op (does not advance queue)", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2", "/tmp/b.lua"))
      -- r1 is active, r2 is queued
      rq.on_complete("unknown-id")
      -- r1 must still be active; r2 must still be queued
      local active = rq.get_active()
      assert.is_not_nil(active)
      assert.are.equal("r1", active.request_id)
      assert.are.equal(1, rq.count(), "queue must not have advanced on unknown on_complete")
    end)

    it("on_complete called twice for the same request_id is idempotent (second call no-op)", function()
      local open_calls = {}
      rq.set_open_fn(function(p)
        table.insert(open_calls, p.request_id)
      end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2", "/tmp/b.lua"))

      -- Complete r1 (first call) — advances queue to r2
      rq.on_complete("r1")
      local active_after_first = rq.get_active()
      assert.is_not_nil(active_after_first)
      assert.are.equal("r2", active_after_first.request_id)
      assert.are.equal(0, rq.count())

      -- Second on_complete("r1") — r1 is no longer active, r2 is. Must be no-op.
      rq.on_complete("r1")
      local active_after_second = rq.get_active()
      assert.is_not_nil(active_after_second, "r2 must remain active after duplicate on_complete(r1)")
      assert.are.equal("r2", active_after_second.request_id)
      assert.are.equal(0, rq.count(), "queue must not advance further on duplicate on_complete")
    end)

    it("on_complete matching active clears it and advances queue", function()
      local open_calls = {}
      rq.set_open_fn(function(p)
        table.insert(open_calls, p.request_id)
      end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2", "/tmp/b.lua"))
      rq.enqueue(make_req("r3", "/tmp/c.lua"))

      assert.are.equal(2, rq.count())
      rq.on_complete("r1")
      assert.are.equal("r2", rq.get_active().request_id)
      assert.are.equal(1, rq.count())
      rq.on_complete("r2")
      assert.are.equal("r3", rq.get_active().request_id)
      assert.are.equal(0, rq.count())
      rq.on_complete("r3")
      assert.is_nil(rq.get_active())
      assert.are.equal(0, rq.count())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 10: drain() idempotency
  -- ---------------------------------------------------------------------------

  describe("review_queue: drain idempotency", function()
    it("calling drain twice when active is nil and queue is empty is safe", function()
      rq.set_open_fn(function(_) end)
      assert.has_no.errors(function()
        rq.drain()
        rq.drain()
      end)
      assert.is_nil(rq.get_active())
    end)

    it("drain while active is set is a no-op (does not replace active)", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2", "/tmp/b.lua"))
      -- r1 is active; drain must leave it untouched
      rq.drain()
      assert.are.equal("r1", rq.get_active().request_id)
      assert.are.equal(1, rq.count(), "queue must not have been popped by drain while active")
    end)

    it("drain when active is nil pops the front of the queue and sets active", function()
      rq.set_open_fn(function(_) end)
      -- Manually set up a queue without an active review by using hold gate
      package.loaded["neph.internal.gate"] = {
        get = function()
          return "hold"
        end,
      }
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2", "/tmp/b.lua"))
      assert.is_nil(rq.get_active())
      assert.are.equal(2, rq.count())
      -- Release gate so drain proceeds normally
      package.loaded["neph.internal.gate"] = {
        get = function()
          return "normal"
        end,
      }
      rq.drain()
      assert.is_not_nil(rq.get_active())
      assert.are.equal("r1", rq.get_active().request_id)
      assert.are.equal(1, rq.count())
      package.loaded["neph.internal.gate"] = nil
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 11: enqueue_front vs enqueue ordering guarantee
  -- ---------------------------------------------------------------------------

  describe("review_queue: enqueue_front ordering", function()
    it("enqueue_front when active is idle opens immediately (same as enqueue)", function()
      local calls = {}
      rq.set_open_fn(function(p)
        table.insert(calls, p.request_id)
      end)
      rq.enqueue_front(make_req("front1", "/tmp/front1.lua"))
      flush()
      assert.are.equal(1, #calls)
      assert.are.equal("front1", calls[1])
    end)

    it("enqueue_front jumps ahead of enqueue items when active is set", function()
      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua")) -- becomes active
      rq.enqueue(make_req("r2", "/tmp/b.lua")) -- queued at back
      rq.enqueue_front(make_req("front1", "/tmp/front.lua")) -- jumps to front

      local q = rq.get_queue()
      assert.are.equal(2, #q)
      assert.are.equal("front1", q[1].request_id, "enqueue_front item must be at queue position 1")
      assert.are.equal("r2", q[2].request_id, "enqueue item must remain at position 2")
    end)

    it("enqueue after enqueue_front when both active: front item is served before enqueue item", function()
      local open_order = {}
      rq.set_open_fn(function(p)
        table.insert(open_order, p.request_id)
      end)
      rq.enqueue(make_req("r1", "/tmp/a.lua")) -- r1 active
      rq.enqueue(make_req("r2", "/tmp/b.lua")) -- r2 queued
      rq.enqueue_front(make_req("front1", "/tmp/front.lua")) -- front1 jumps ahead of r2

      -- Complete r1 → front1 should be next
      rq.on_complete("r1")
      assert.are.equal("front1", rq.get_active().request_id)

      -- Complete front1 → r2 is next
      rq.on_complete("front1")
      assert.are.equal("r2", rq.get_active().request_id)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Issue 12: reject_all_pending only affects queued items, not active
  -- ---------------------------------------------------------------------------

  describe("review_queue: reject_all_pending scope", function()
    it("reject_all_pending does not clear the active review", function()
      package.loaded["neph.api.review"] = {
        write_result = function(_, _, _, _) end,
      }
      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2", "/tmp/b.lua"))
      rq.enqueue(make_req("r3", "/tmp/c.lua"))

      -- r1 is active; r2 and r3 are queued
      rq.reject_all_pending("test exit")

      -- Active must still be r1
      local active = rq.get_active()
      assert.is_not_nil(active, "active review must not be cleared by reject_all_pending")
      assert.are.equal("r1", active.request_id)
      -- Queue must be empty
      assert.are.equal(0, rq.count())

      package.loaded["neph.api.review"] = nil
    end)

    it("reject_all_pending on an empty queue is a no-op", function()
      rq.set_open_fn(function(_) end)
      assert.has_no.errors(function()
        rq.reject_all_pending("Neovim exiting")
      end)
      assert.are.equal(0, rq.count())
    end)

    it("reject_all_pending calls write_result for each queued item", function()
      local written = {}
      package.loaded["neph.api.review"] = {
        write_result = function(_, _, request_id, envelope)
          table.insert(written, { request_id = request_id, decision = envelope.decision })
        end,
      }
      rq.set_open_fn(function(_) end)
      rq.enqueue(make_req("r1", "/tmp/a.lua"))
      rq.enqueue(make_req("r2", "/tmp/b.lua"))
      rq.enqueue(make_req("r3", "/tmp/c.lua"))
      -- r1 is active; r2, r3 queued
      rq.reject_all_pending("shutdown")

      assert.are.equal(2, #written, "write_result must be called for each queued item (r2, r3)")
      local ids = {}
      for _, w in ipairs(written) do
        table.insert(ids, w.request_id)
        assert.are.equal("reject", w.decision)
      end
      table.sort(ids)
      assert.are.same({ "r2", "r3" }, ids)

      package.loaded["neph.api.review"] = nil
    end)
  end)
end)
