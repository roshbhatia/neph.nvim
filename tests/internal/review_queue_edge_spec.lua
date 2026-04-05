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
-- ---------------------------------------------------------------------------

before_each(function()
  package.loaded["neph.internal.review_queue"] = nil
  rq = require("neph.internal.review_queue")
end)

after_each(function()
  if rq then
    rq._reset()
  end
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
